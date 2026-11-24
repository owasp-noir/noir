require "./aspnet_auth"

# Razor Pages and Blazor components declare their authorization in markup
# directives, in the page model or component class, and (Razor Pages) in
# `RazorPagesOptions.Conventions`. The endpoint's code path is the
# `.cshtml` / `.razor` file holding the `@page` directive.
class AspnetAuthTagger < FrameworkTagger
  # An unclosed `@*` runs to the end of the file.
  RAZOR_COMMENT       = %r{@\*.*?(?:\*@|\z)}m
  ATTRIBUTE_DIRECTIVE = /^[ \t]*@attribute[ \t]+(\[.*\])[ \t]*$/
  # Razor reads `@model` inside a `@{ }` block too.
  MODEL_DIRECTIVE    = /^[ \t]*@model[ \t]+([\w.]+)/m
  INHERITS_DIRECTIVE = /^[ \t]*@inherits[ \t]+([\w.]+)/m
  MAP_COMPONENTS     = /\bMapRazorComponents\s*</
  PAGE_CONVENTION    = /\.\s*(Authorize(?:Area)?(?:Page|Folder)|AllowAnonymousTo(?:Area)?(?:Page|Folder))\s*\(/

  # A `PageConventionCollection` call (`AuthorizeFolder("/Admin", "Ops")`):
  # its page name or folder and area, nil when either is not a literal or an
  # argument is named, and its policy argument's text. `certain` is false
  # for a call under a condition, or in a project that moves the pages root
  # (`RootDirectory`), whose reach this does not follow.
  record PageConvention, name : String, target : String?, area : String?, policy : String?,
    text : String, path : String, line : Int32, certain : Bool do
    def anonymous? : Bool
      name.starts_with?("AllowAnonymous")
    end

    def folder? : Bool
      name.ends_with?("Folder")
    end
  end

  @page_conventions : Hash(String?, Array(PageConvention))? = nil
  @component_roots : Set(String?)? = nil
  @razor_attrs = Hash(String, Array(Attr)).new
  @cs_by_lower : Hash(String, String)? = nil

  private def check_razor_endpoint(endpoint : Endpoint) : Nil
    file = endpoint.details.code_paths.first?.try(&.path) || return
    case File.extname(file).downcase
    when ".cshtml" then check_razor_page(endpoint, file)
    when ".razor"  then check_component(endpoint, file)
    end
  end

  # ASP.NET reads a page's authorization from the page's own `@attribute`s
  # and, when its `@model` is a `PageModel`, from that class and its bases
  # (`DefaultPageApplicationModelProvider`): a model named only by file
  # convention (`Index.cshtml.cs`, no `@model`) is not bound. Conventions
  # add an `[Authorize]` or `[AllowAnonymous]` per page or folder, and an
  # `[AllowAnonymous]` from any source lifts the rest.
  private def check_razor_page(endpoint : Endpoint, file : String) : Nil
    markup = razor_markup(file) || return
    page_attrs = razor_attributes(file)
    chain = page_model_chain(file, markup)
    layers = [{page_attrs, file}] + chain.map { |decl| {decl.attributes, decl.path} }
    lists = layers.map(&.[0])
    conventions = page_conventions_for(file)
    return if lists.any? { |attrs| anonymous?(attrs) } || derived_attribute(lists, :anonymous)
    return if conventions.any? { |conv| conv.anonymous? && conv.target && conv.certain }

    description = nil
    chain.each_with_index do |decl, i|
      text = authorize_description(decl.attributes) || next
      description = "#{text} (#{i == 0 ? "PageModel" : "inherited from #{decl.name}"})"
      break
    end
    description ||= authorize_description(page_attrs).try { |text| "#{text} (page)" }
    description ||= derived_attribute(lists, :authorize).try { |derived| "[#{derived[0]}] (derives AuthorizeAttribute)" }
    description ||= conventions.find { |conv| !conv.anonymous? }.try { |conv| "ASP.NET Razor Pages convention #{conv.text}" }
    return unless description

    default = default_policy
    clauses = attribute_clauses(layers, default)
    conventions.each do |conv|
      next if conv.anonymous?
      # `AuthorizePage(name)` passes `string.Empty`, which means the default policy.
      policy = conv.policy.try { |text| Noir::CSharpDecl.literal(text) == "" ? nil : text }
      read = Access.clauses(AspnetAccess.authorize(policy, default), conv.text, conv.path, conv.line)
      unless conv.certain
        unread = Access::Atom.new(:unresolved, "#{conv.text} (conditional)")
        read = read.map { |clause| Access::Clause.new(clause.any_of + [unread], clause.source, clause.path, clause.line) }
      end
      clauses.concat(read)
    end
    # An `AllowAnonymousTo*` whose reach this cannot read may lift every layer.
    conventions.each do |conv|
      next if !conv.anonymous? || (conv.target && conv.certain)
      unread = Access::Atom.new(:unresolved, conv.text)
      clauses = clauses.map { |clause| Access::Clause.new(clause.any_of + [unread], clause.source, clause.path, clause.line) }
    end
    endpoint.add_tag(guard_tag("Protected by #{description}", clauses.uniq(&.any_of)))
  end

  # A routable component's attributes, its class's and its bases'
  # (`GetCustomAttributes(inherit: true)`), are its endpoint's metadata
  # (`RazorComponentEndpointFactory`); each `_Imports.razor` from its folder
  # up to its project adds its `@attribute`s. Only a server mapping
  # components with `MapRazorComponents` enforces them: a WebAssembly app,
  # or a Blazor Server app routing inside the circuit, checks them in the
  # client, so its route stays unguarded here. MVC filters do not run.
  private def check_component(endpoint : Endpoint, file : String) : Nil
    return unless component_roots.includes?(nearest_project_root(file, CSPROJ))
    markup = razor_markup(file) || return
    labeled = [{razor_attributes(file), file, "Blazor component"}]
    own, chain = component_chain(file, markup)
    chain.each_with_index do |decl, i|
      labeled << {decl.attributes, decl.path, own && i == 0 ? "Blazor component" : "inherited from #{decl.name}"}
    end
    imports(file).each { |path| labeled << {razor_attributes(path), path, "_Imports.razor"} }
    layers = labeled.map { |attrs, path, _| {attrs, path} }
    lists = layers.map(&.[0])
    return if lists.any? { |attrs| anonymous?(attrs) } || derived_attribute(lists, :anonymous)

    description = nil
    labeled.each do |attrs, _, label|
      text = authorize_description(attrs) || next
      description = "#{text} (#{label})"
      break
    end
    description ||= derived_attribute(lists, :authorize).try { |derived| "[#{derived[0]}] (derives AuthorizeAttribute)" }
    return unless description

    default = default_policy
    clauses = layers.flat_map { |attrs, path| attrs.flat_map { |attr| authorize_clauses(attr, path, default) } }
    endpoint.add_tag(guard_tag("Protected by #{description}", clauses.uniq(&.any_of)))
  end

  # Project roots whose components a server maps: each one calling
  # `MapRazorComponents`, and a project it references that it names in
  # `AddAdditionalAssemblies(typeof(T).Assembly)` (`T` declared there, or a
  # namespace-qualified `_Imports` naming that project). A referenced
  # WebAssembly client or class library it does not name is not served.
  private def component_roots : Set(String?)
    @component_roots ||= begin
      roots = Set(String?).new
      collect_files_by_extension(".cs").each do |path|
        next unless read_file(path).try(&.includes?("MapRazorComponents"))
        next if base_relative_path(path).matches?(TEST_PATH)
        masked = lexer_for(path).try(&.masked_source) || next
        next unless masked.matches?(MAP_COMPONENTS)
        host = nearest_project_root(path, CSPROJ) || next
        roots << host
        referenced = project_closure([host], project_references)
        masked.scan(/\bAddAdditionalAssemblies\s*\(([^;]*)/) do |call|
          call[1].scan(/\btypeof\s*\(\s*([\w.]+)\s*\)/) do |type|
            names = type[1].split('.')
            candidates = if names.last == "_Imports"
                           qualifier = names[0...-1].join('.')
                           referenced.select { |dir| !qualifier.empty? && File.basename(dir).compare(qualifier, case_insensitive: true) == 0 }
                         else
                           (class_files[names.last]? || [] of String).compact_map { |file| nearest_project_root(file, CSPROJ) }
                         end
            candidates.each { |dir| roots << dir if referenced.includes?(dir) }
          end
        end
      end
      roots
    end
  end

  # A markup file with its `@* *@` comments blanked, newlines kept.
  private def razor_markup(path : String) : String?
    read_file(path).try(&.gsub(RAZOR_COMMENT) { |comment| "\n" * comment.count('\n') })
  end

  # The `@attribute [...]` directives of a markup file, parsed as the
  # attribute lists of a class, each on its own line.
  private def razor_attributes(path : String) : Array(Attr)
    @razor_attrs[path] ||= begin
      lines = (razor_markup(path) || "").lines.map { |line| line.match(ATTRIBUTE_DIRECTIVE).try(&.[1]) || "" }
      if lines.all?(&.empty?)
        [] of Attr
      else
        source = lines.join('\n') + "\nclass RazorDirectives {}\n"
        Noir::CSharpDeclParser.parse(Noir::CSharpLexer.new(source)).types.first?.try(&.attributes) || [] of Attr
      end
    end
  end

  # The `@model` class and its bases, when it is a `PageModel`.
  private def page_model_chain(file : String, markup : String) : Array(ClassDecl)
    model = markup.match(MODEL_DIRECTIVE).try(&.[1].split('.').last) || return [] of ClassDecl
    chain = scoped_chain(model, file)
    chain.any?(&.base.== "PageModel") ? chain : [] of ClassDecl
  end

  # `{true, the component's code-behind partial class (`Cart.razor.cs`)
  # and its bases}` or `{false, }`, followed by its `@inherits` base and
  # that one's bases.
  private def component_chain(file : String, markup : String) : Tuple(Bool, Array(ClassDecl))
    name = File.basename(file, File.extname(file))
    inherited = markup.match(INHERITS_DIRECTIVE).try { |found| scoped_chain(found[1].split('.').last, file) } || [] of ClassDecl
    if (behind = code_behind(file)) && (type = unit_for(behind).try(&.types.find { |decl| decl.kind == "class" && decl.name == name }))
      return {true, class_chain(behind, type.line) + inherited}
    end
    {false, inherited}
  end

  # Class `name` as the page or component at `file` sees it, then its
  # bases: looked up from its code-behind's namespace, else the one
  # declaration in its project or a project it references. A namesake in
  # another project of the scan is not it.
  private def scoped_chain(name : String, file : String) : Array(ClassDecl)
    visible = visible_roots(nearest_project_root(file, CSPROJ))
    decls = if behind = code_behind(file)
              class_decls(name, behind)
            else
              files = (class_files[name]? || [] of String).select { |path| visible.includes?(nearest_project_root(path, CSPROJ)) }
              files.size == 1 ? class_decls(name, files.first) : [] of ClassDecl
            end
    decls = decls.select { |decl| visible.includes?(nearest_project_root(decl.path, CSPROJ)) }
    return decls if decls.empty?
    bases = ancestors(decls.compact_map(&.base).first?, decls.first.path, Set{name})
    decls + bases.take_while { |decl| visible.includes?(nearest_project_root(decl.path, CSPROJ)) }
  end

  # `Index.cshtml.cs` beside `Index.cshtml`, matched case-insensitively as
  # the analyzer does.
  private def code_behind(file : String) : String?
    index = @cs_by_lower ||= collect_files_by_extension(".cs").index_by(&.downcase)
    index["#{file}.cs".downcase]?
  end

  # Each `_Imports.razor` from the component's folder up to its project root.
  private def imports(file : String) : Array(String)
    root = nearest_project_root(file, CSPROJ)
    found = [] of String
    dir = File.dirname(file)
    loop do
      candidate = File.join(dir, "_Imports.razor")
      found << candidate if candidate != file && read_file(candidate)
      break if root.nil? || Noir::PathScope.expand(dir) == root
      parent = File.dirname(dir)
      break if parent == dir
      dir = parent
    end
    found
  end

  # The conventions of the page's project that reach it, plus each
  # `AllowAnonymousTo*` there whose page is not a literal.
  private def page_conventions_for(file : String) : Array(PageConvention)
    area, page = view_engine_path(base_relative_path(file)) || return [] of PageConvention
    (page_conventions[nearest_project_root(file, CSPROJ)]? || [] of PageConvention).select do |conv|
      target = conv.target
      next conv.anonymous? if target.nil?
      next false unless (conv.area || "").compare(area || "", case_insensitive: true) == 0
      conv.folder? ? folder_reaches?(target, page) : target.compare(page, case_insensitive: true) == 0
    end
  end

  # `PageConventionCollection.PathBelongsToFolder`, after its
  # `FolderApplicationModelConvention` trims the trailing `/`.
  private def folder_reaches?(folder : String, page : String) : Bool
    folder = folder.rstrip('/')
    return true if folder.empty?
    page.size > folder.size && page.downcase.starts_with?(folder.downcase) && page[folder.size] == '/'
  end

  # `{area, page name}`: `Pages/Basket/Checkout.cshtml` is `/Basket/Checkout`,
  # `Areas/Identity/Pages/Account/Login.cshtml` area `Identity`, page
  # `/Account/Login`.
  private def view_engine_path(relative : String) : Tuple(String?, String)?
    segments = relative.rchop(File.extname(relative)).split('/').reject(&.empty?)
    root = segments.index("Pages") || return
    area = segments[root - 1] if root >= 2 && segments[root - 2] == "Areas"
    {area, "/" + segments[(root + 1)..].join('/')}
  end

  # Every `PageConventionCollection` authorization call in live, non-test
  # code, by project root.
  private def page_conventions : Hash(String?, Array(PageConvention))
    @page_conventions ||= begin
      found = Hash(String?, Array(PageConvention)).new
      moved = Set(String?).new
      collect_files_by_extension(".cs").each do |path|
        next unless read_file(path).try(&.includes?("RootDirectory"))
        next if base_relative_path(path).matches?(TEST_PATH)
        moved << nearest_project_root(path, CSPROJ) if lexer_for(path).try(&.masked_source.matches?(/\bRootDirectory\s*=(?![=>])/))
      end
      collect_files_by_extension(".cs").each do |path|
        content = read_file(path) || next
        next unless content.includes?("Conventions") && content.matches?(PAGE_CONVENTION)
        next if base_relative_path(path).matches?(TEST_PATH)
        lexer = lexer_for(path) || next
        masked = lexer.masked_source
        next if masked.includes?("WebApplicationFactory")
        code = lexer.code_source
        masked.scan(PAGE_CONVENTION) do |call|
          close = lexer.matching_delimiter(call.end(0) - 1) || next
          name = call[1]
          text = code[call.end(0)...close]
          args = Noir::TopLevelSplit.split(text, ',', AspnetAccess::SPLIT).map(&.strip)
          # A named argument may bind any parameter: its reach is not read.
          named = args.any?(&.matches?(/\A@?\w+\s*:(?!:)/))
          area = name.includes?("Area") ? args.shift? : nil
          target = args.shift?.try { |arg| Noir::CSharpDecl.literal(arg) }
          area_name = area.try { |arg| Noir::CSharpDecl.literal(arg) }
          target = nil if named || (area && area_name.nil?)
          root = nearest_project_root(path, CSPROJ)
          certain = !moved.includes?(root) && !conditional?(masked, call.begin(0))
          (found[root] ||= [] of PageConvention) << PageConvention.new(
            name, target, area_name, args.shift?, "#{name}(#{text.strip})", path, code[0, call.begin(0)].count('\n') + 1, certain)
        end
      end
      found
    end
  end
end
