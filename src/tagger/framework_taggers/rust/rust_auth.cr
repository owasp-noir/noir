require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../prefix_scope"
require "../../../miniparsers/rust_request_guards"
require "../../../miniparsers/rust_use_imports"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../utils/c_comments"

@[Noir::TaggerFor(key: "rust_auth", name: "Rust Auth Tagger", desc: "Identifies Rust authentication patterns (guards, extractors, middleware)", order: 70)]
class RustAuthTagger < FrameworkTagger
  class RustFnEntry
    getter file_path : String
    getter name : String
    getter module_path : Array(String)
    getter body_text : String
    # Leaf types of the parameters that must extract for the fn to run.
    getter required_params : Array(String)

    def initialize(@file_path : String, @name : String, @module_path : Array(String), @body_text : String, @required_params : Array(String))
    end

    def full_path : String
      if @module_path.empty?
        @name
      else
        "#{@module_path.join("::")}::#{@name}"
      end
    end
  end

  # Actix-Web auth middleware/extractor patterns
  ACTIX_AUTH_PATTERNS = [
    /HttpAuthentication/,
    /BearerAuth/,
    /BasicAuth/,
    /Identity/,
  ]

  # Rocket request guard types (in function signatures)
  GUARD_TYPE_PATTERNS = [
    /\b(?:Auth|Authenticated|AuthGuard|AuthUser|AuthToken)\b/,
    /\b(?:ApiKey|ApiToken|BearerToken|AccessToken)\b/,
    /\b(?:Claims|JwtClaims|TokenClaims|JwtToken)\b/,
    /\b(?:AdminUser|AdminGuard|Admin)\b/,
    /\b(?:UserGuard|UserToken|CurrentUser|LoggedInUser)\b/,
    /\b(?:Session|SessionUser|CookieAuth)\b/,
    /\b(?:RoleGuard|Permission|Authorized)\b/,
  ]

  # Axum extractor patterns
  AXUM_EXTRACTOR_PATTERNS = [
    /Extension<.*(?:Auth|Claims|Token|User|Session).*>/,
    /TypedHeader<.*(?:Authorization|Bearer).*>/,
  ]

  # Middleware layer patterns (in Router/App setup)
  MIDDLEWARE_LAYER_PATTERNS = [
    /\.wrap\s*\(\s*(\w*[Aa]uth\w*)/,
    /\.wrap\s*\(\s*HttpAuthentication/,
    # ntex spells actix's `.wrap(...)` as `.middleware(...)`.
    /\.middleware\s*\(\s*(\w*[Aa]uth\w*)/,
  ]

  # A 401/403 a middleware answers itself: a status, an actix error helper,
  # or an error variant spelled as one (`AuthError::Unauthorized`).
  MIDDLEWARE_REFUSAL = /#{Noir::RustRequestGuards::REFUSAL_RE}|\b\w+::(?:Unauthori[sz]ed|Unauthenticated|Forbidden)\b/
  # An error whose status is decided elsewhere: `Err(...)`, `ctx?`, `f()?`.
  ERROR_EXIT = /\bErr\s*\(|[\w)]\?/
  # A path compared against (`res.status() == StatusCode::UNAUTHORIZED`):
  # read, not answered.
  COMPARED  = /(?:\w+::)*\w+\s*[=!]=|[=!]=\s*(?:\w+::)*\w+/
  AUTH_NAME = /auth|jwt|bearer/i
  HANDED_ON = /\blet\s+(?:mut\s+)?\w+\s*(?::[^=;]+)?=\s*next\s*\.\s*run\s*\(/
  CSRF_NAME = /[\w-]*(?:csrf|xsrf)[\w-]*/i
  # What a middleware reads to tell who the caller is (CSRF names cut out).
  CREDENTIAL = /authoriz|bearer|jwt|token|api[-_]?key|claims|session|login/i

  # Guard/middleware attribute patterns
  GUARD_ATTRIBUTE_PATTERNS = [
    /#\[guard\s*=\s*"(\w+)"\]/,
    /#\[.*guard.*\]/i,
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @middleware_scopes = [] of {prefix: String, exact: Bool, local: Bool, description: String}
    @guard_verdicts = {} of String => Bool
    @handler_param_types = {} of String => Hash(Int32, Array(String))
    @fn_index = Hash(String, Array(RustFnEntry)).new
    @crate_fn_index = Hash(String, Array(RustFnEntry)).new
    @file_fn_index = Hash(String, Hash(String, RustFnEntry)).new
    @file_imports = Hash(String, Noir::RustUseImports::Imports).new
    @fn_mounts_cache = Hash(String, Array({String, String})).new
    @fn_files_by_name = Hash(String, Array(String)).new
    @fn_file_order = Hash(String, Int32).new
    @fn_indexed_files = Set(String).new
  end

  def self.target_techs : Array(String)
    [
      "rust_axum", "rust_rocket", "rust_actix_web",
      "rust_loco", "rust_rwf", "rust_tide",
      "rust_warp", "rust_gotham", "rust_ntex",
    ]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # Middleware is judged by the request guards it extracts, so those first.
    pre_scan_request_guards
    pre_scan_middleware_scopes
    super
  end

  # Which `FromRequest` / `FromRequestParts` types in the scan can refuse
  # the caller, decided by their impls (see `Noir::RustRequestGuards`).
  private def pre_scan_request_guards
    facts = Noir::RustRequestGuards::Facts.new
    collect_files_by_extension(".rs").each do |file|
      next unless content = read_file(file)
      Noir::RustRequestGuards.scan(content, facts, file)
    rescue e
      @logger.debug "rust request-guard scan error #{file}: #{e}"
    end
    @guard_verdicts = Noir::RustRequestGuards.resolve(facts)
  end

  # The first parameter of the endpoint's handler fn whose type is a
  # request guard that can refuse the caller.
  private def handler_request_guard(endpoint : Endpoint) : String?
    return if @guard_verdicts.empty?
    handler = endpoint.handler || return
    path = handler.path || return
    line = handler.line || return
    types = @handler_param_types[path] ||= begin
      content = read_file(path)
      content ? Noir::RustRequestGuards.handler_param_types(content) : {} of Int32 => Array(String)
    end
    types[line]?.try &.find { |type| @guard_verdicts[type]? == true }
  end

  private def pre_scan_middleware_scopes
    @middleware_scopes.clear
    @fn_index.clear
    @crate_fn_index.clear
    @file_fn_index.clear
    @file_imports.clear
    @fn_mounts_cache.clear
    @fn_files_by_name.clear
    @fn_file_order.clear
    @fn_indexed_files.clear

    files = collect_files_by_extension(".rs")
    build_function_index(files)
    scan_axum_layers(files)
    scan_actix_scope_middleware(files)
  end

  FN_NAME_RE = /\bfn\s+(?:r#)?([A-Za-z_]\w*)/

  # Only records which files declare which fn names (a regex, no parse). A
  # file is parsed into the fn index when a lookup needs it
  # (`ensure_fn_indexed`): the whole-project parse used to cost more than
  # every other pass of this tagger on a big workspace.
  private def build_function_index(files : Array(String))
    files.each_with_index do |file, order|
      content = read_file(file) || next
      @fn_file_order[file] = order
      names = Set(String).new
      content.scan(FN_NAME_RE) { |m| names << m[1] }
      names.each { |name| (@fn_files_by_name[name] ||= [] of String) << file }
    end
  end

  private def ensure_fn_indexed(file : String) : Nil
    return unless @fn_indexed_files.add?(file)
    content = read_file(file) || return
    begin
      Noir::TreeSitter.parse_rust(content) do |root|
        collect_functions_in_node(root, content, file, file_module_parts(file), [] of String)
      end
    rescue e
      @logger.debug "rust function index error in #{file}: #{e}"
    end
  end

  # Every file declaring a fn named like the last segment of `ref`.
  private def ensure_fn_ref_indexed(ref : String) : Nil
    @fn_files_by_name[ref.rpartition("::")[2]]?.try &.each { |file| ensure_fn_indexed(file) }
  end

  # Entries in scan order, as the eager index registered them.
  private def in_scan_order(entries : Array(RustFnEntry)) : Array(RustFnEntry)
    entries.each_with_index.to_a.sort_by { |(entry, idx)| {@fn_file_order[entry.file_path]? || 0, idx} }.map(&.[0])
  end

  private def file_module_parts(file_path : String) : Array(String)
    rel = base_relative_path(file_path).lchop("src/")
    parts = rel.split(File::SEPARATOR).reject(&.empty?)
    return [] of String if parts.empty?

    last = parts.last
    if last.ends_with?(".rs")
      base = last[0...-3]
      if base == "main" || base == "lib" || base == "mod"
        parts.pop
      else
        parts[-1] = base
      end
    end
    parts
  end

  private def collect_functions_in_node(
    node : LibTreeSitter::TSNode,
    source : String,
    file_path : String,
    file_mod_parts : Array(String),
    inline_mod_stack : Array(String),
  )
    Noir::TreeSitter.each_named_child(node) do |child|
      case Noir::TreeSitter.node_type(child)
      when "mod_item"
        name_node = Noir::TreeSitter.field(child, "name")
        if name_node
          mod_name = Noir::TreeSitter.node_text(name_node, source)
          if body_node = Noir::TreeSitter.field(child, "body")
            inline_mod_stack.push(mod_name)
            collect_functions_in_node(body_node, source, file_path, file_mod_parts, inline_mod_stack)
            inline_mod_stack.pop
          end
        end
      when "function_item"
        name_node = Noir::TreeSitter.field(child, "name")
        if name_node
          fn_name = Noir::TreeSitter.node_text(name_node, source).lchop("r#")
          body_node = Noir::TreeSitter.field(child, "body")
          body_text = body_node ? Noir::TreeSitter.node_text(body_node, source) : ""
          full_mod = file_mod_parts + inline_mod_stack

          entry = RustFnEntry.new(file_path, fn_name, full_mod, body_text, required_param_types(child, body_text, source))
          register_function(entry)
        end
      else
        collect_functions_in_node(child, source, file_path, file_mod_parts, inline_mod_stack)
      end
    end
  end

  # All but `Option<X>`, and `Result<X, _>` only when the body `?`s it
  # (`ctx: Result<CtxW>` then `ctx?`).
  private def required_param_types(fn_node : LibTreeSitter::TSNode, body : String, source : String) : Array(String)
    types = [] of String
    params = Noir::TreeSitter.field(fn_node, "parameters") || return types
    Noir::TreeSitter.each_named_child(params) do |param|
      next unless Noir::TreeSitter.node_type(param) == "parameter"
      type_node = Noir::TreeSitter.field(param, "type") || next
      type = Noir::TreeSitter.node_text(type_node, source)
      leaf = Noir::RustRequestGuards.type_leaf(type) || next
      next if leaf == "Option"
      if leaf == "Result"
        name = Noir::TreeSitter.field(param, "pattern").try { |pattern| Noir::TreeSitter.node_text(pattern, source) } || next
        next unless body.matches?(/\b#{Regex.escape(name)}\s*\?/)
        leaf = Noir::RustRequestGuards.type_leaf(type.partition('<')[2]) || next
      end
      types << leaf
    end
    types
  end

  private def register_function(entry : RustFnEntry)
    full = entry.full_path
    (@fn_index[full] ||= [] of RustFnEntry) << entry

    parts = entry.module_path + [entry.name]
    (1...parts.size).each do |start_idx|
      suffix = parts[start_idx..].join("::")
      (@fn_index[suffix] ||= [] of RustFnEntry) << entry
    end

    (@fn_index[entry.name] ||= [] of RustFnEntry) << entry

    # A workspace crate's fn under its crate name, as another crate `use`s it:
    # `crates/libs/lib-web/src/a/b.rs` -> `lib_web::a::b::f`.
    if (src = parts.rindex("src")) && src > 0
      crate_key = ([parts[src - 1].tr("-", "_")] + parts[(src + 1)..]).join("::")
      (@crate_fn_index[crate_key] ||= [] of RustFnEntry) << entry
    end

    file_map = (@file_fn_index[entry.file_path] ||= Hash(String, RustFnEntry).new)
    file_map[entry.name] ||= entry
    file_map[full] ||= entry
  end

  private def file_imports_for(file_path : String) : Noir::RustUseImports::Imports
    @file_imports[file_path] ||= begin
      content = read_file(file_path) || ""
      Noir::RustUseImports.parse(content)
    end
  end

  private def lookup_function(fn_ref : String, from_file : String) : RustFnEntry?
    cleaned = fn_ref.lchop("::").lchop("crate::").lchop("self::")
    parts = cleaned.split("::")
    ensure_fn_indexed(from_file)
    ensure_fn_ref_indexed(cleaned)

    if parts.size == 1
      if same_file_entry = @file_fn_index[from_file]?.try(&.[cleaned]?)
        return same_file_entry
      end
    end

    imports = file_imports_for(from_file)
    if parts.size == 1
      if imported_full = imports.names[cleaned]?
        cleaned = imported_full.lchop("::").lchop("crate::")
      end
    elsif first_imported = imports.names[parts[0]]?
      cleaned = (first_imported.split("::") + parts[1..]).join("::").lchop("::").lchop("crate::")
    end

    ensure_fn_ref_indexed(cleaned)
    if matches = @fn_index[cleaned]?
      if same_file = matches.find { |e| e.file_path == from_file }
        return same_file
      end
      return in_scan_order(matches).first
    end

    @crate_fn_index[cleaned]?.try { |crate_matches| nearest_crate_entry(in_scan_order(crate_matches), from_file) }
  end

  # The crate-keyed fn sharing the longest path prefix with `from_file`, so
  # each app of a monorepo reaches its own `web` crate. Two crate dirs tied
  # for it resolve to nothing.
  private def nearest_crate_entry(entries : Array(RustFnEntry), from_file : String) : RustFnEntry?
    from = from_file.split(File::SEPARATOR)
    shared = entries.map do |entry|
      parts = entry.file_path.split(File::SEPARATOR)
      from.zip?(parts).index { |(a, b)| a != b } || [from.size, parts.size].min
    end
    best = shared.max
    nearest = entries.each_index.select { |i| shared[i] == best }.map { |i| entries[i] }.to_a
    crate_dirs = nearest.map { |entry| entry.file_path.rpartition("#{File::SEPARATOR}src#{File::SEPARATOR}")[0] }.uniq!
    crate_dirs.size == 1 ? nearest.first : nil
  end

  private def scan_axum_layers(files : Array(String))
    files.each do |file|
      content = read_file(file) || next
      next unless content.includes?("layer(")

      begin
        Noir::TreeSitter.parse_rust(content) do |root|
          Noir::TreeSitter.walk(root) do |node|
            next unless Noir::TreeSitter.node_type(node) == "call_expression"

            field = field_call_name(node, content)
            next unless field == "route_layer" || field == "layer"

            args = named_call_args(node)
            next if args.empty?

            middleware_name = layer_guard(args[0], content, file)
            next unless middleware_name

            mounts = collect_axum_layer_mounts(node, content, file)
            mounts.each do |kind, path|
              @middleware_scopes << {
                prefix:      path,
                exact:       kind == "route",
                local:       true,
                description: "Protected by Rust #{middleware_name} middleware on #{path}",
              }
            end
          end
        end
      rescue e
        @logger.debug "axum layer scan error in #{file}: #{e}"
      end
    end
  end

  # The value of the last `let name = ...` in a block enclosing `use`, within
  # its fn, that ends before `use` starts: `let app = app.layer(x)` reads
  # the earlier `app`, never itself.
  private def let_value(use : LibTreeSitter::TSNode, name : String, source : String) : LibTreeSitter::TSNode?
    use_start = LibTreeSitter.ts_node_start_byte(use)
    node = use
    while parent = Noir::TreeSitter.parent(node)
      if Noir::TreeSitter.node_type(parent) == "block"
        found = nil
        Noir::TreeSitter.each_named_child(parent) do |stmt|
          next unless Noir::TreeSitter.node_type(stmt) == "let_declaration"
          next unless LibTreeSitter.ts_node_end_byte(stmt) <= use_start
          pattern = Noir::TreeSitter.field(stmt, "pattern")
          value = Noir::TreeSitter.field(stmt, "value")
          next unless pattern && value && Noir::TreeSitter.node_text(pattern, source) == name
          found = value
        end
        return found if found
      end
      return if Noir::TreeSitter.node_type(parent) == "function_item"
      node = parent
    end
    nil
  end

  # The name a layer argument guards under, or nil when it does not guard.
  # `from_fn(f)` / `from_fn_with_state(s, f)` is judged by `f`; any other
  # layer (`AuthLayer::new(..)`, `auth_layer`) by the name it is built from.
  private def layer_guard(arg : LibTreeSitter::TSNode, source : String, file : String) : String?
    if Noir::TreeSitter.node_type(arg) == "call_expression"
      args = named_call_args(arg)
      case call_func_leaf_name(arg, source)
      when "from_fn"            then return args[0]?.try { |f| middleware_guard(f, source, file) }
      when "from_fn_with_state" then return args[1]?.try { |f| middleware_guard(f, source, file) }
      end
    end
    Noir::TreeSitter.node_text(arg, source).partition('(')[0].match(/\w*[Aa]uth\w*/).try(&.[0])
  end

  # A middleware fn whose definition (or closure) is in the scan guards when
  # its body does; one from a library when its path reads as auth and not
  # CSRF (`axum_auth::require`, `auth::middleware`).
  private def middleware_guard(f : LibTreeSitter::TSNode, source : String, file : String) : String?
    text = Noir::TreeSitter.node_text(f, source).strip
    if Noir::TreeSitter.node_type(f) == "closure_expression"
      return body_guards?("", text, [] of String) ? "closure" : nil
    end
    ref = text.lchop("::").lchop("crate::").lchop("self::")
    segments = ref.split("::")
    name = segments.reverse_each.find(&.matches?(AUTH_NAME)) || segments.last
    if entry = lookup_function(ref, file)
      body_guards?(ref, entry.body_text, entry.required_params) ? name : nil
    elsif ref.matches?(AUTH_NAME) && !ref.matches?(CSRF_NAME)
      name
    end
  end

  # A body refuses the caller through an extractor that refuses, or answers
  # 401/403 (or a redirect to a login page) itself unless all it checks is
  # a CSRF token. An auth-named
  # middleware that exits with an error (`Err(AppError::X)`, `ctx?`) whose
  # status is mapped elsewhere keeps the benefit of its name.
  private def body_guards?(ref : String, body : String, required_params : Array(String)) : Bool
    return true if required_params.any? { |type| @guard_verdicts[type]? == true }
    code = Noir::CComments.strip(body)
    # What a body does to the response it got (`let res = next.run(req).await;`
    # then `if res.status() == 401 { redirect }`) refuses no caller. Only a
    # binding at the body's own top level hands on every request; one in a
    # branch or a closure does not.
    # ponytail: braces are counted raw, so a lone `{` in a string skews it.
    offset = 0
    while handed = code.match(HANDED_ON, offset)
      head = code[0, handed.begin]
      if head.count('{') - head.count('}') == 1
        code = head
        break
      end
      offset = handed.end
    end
    if ref.matches?(CSRF_NAME) || code.matches?(CSRF_NAME)
      return false unless code.gsub(CSRF_NAME, "").matches?(CREDENTIAL)
    end
    code.gsub(COMPARED, "").matches?(MIDDLEWARE_REFUSAL) || code.matches?(Noir::RustRequestGuards::LOGIN_REDIRECT_RE) ||
      (ref.matches?(AUTH_NAME) && code.matches?(ERROR_EXIT))
  end

  private def collect_axum_layer_mounts(
    call : LibTreeSitter::TSNode,
    source : String,
    file_path : String,
  ) : Array({String, String})
    if route_call = find_enclosing_route_call(call, source)
      route_args = named_call_args(route_call)
      if !route_args.empty? && (path = string_literal_content(route_args[0], source))
        return [{"route", path}]
      end
    end

    recv = chain_receiver(call)
    return [] of {String, String} unless recv
    collect_router_mounts(recv, source, file_path)
  end

  private def find_enclosing_route_call(call : LibTreeSitter::TSNode, source : String) : LibTreeSitter::TSNode?
    node = call
    while parent = Noir::TreeSitter.parent(node)
      if Noir::TreeSitter.node_type(parent) == "call_expression"
        if field_call_name(parent, source) == "route"
          args = named_call_args(parent)
          if args.size >= 2
            arg1_start = LibTreeSitter.ts_node_start_byte(args[1]).to_i
            call_start = LibTreeSitter.ts_node_start_byte(call).to_i
            if call_start >= arg1_start
              return parent
            end
          end
        end
      end
      node = parent
    end
    nil
  end

  private def collect_router_mounts(
    node : LibTreeSitter::TSNode,
    source : String,
    file_path : String,
    prefix : String = "",
    visited_fns : Set(String) = Set(String).new,
  ) : Array({String, String})
    mounts = [] of {String, String}
    cursor : LibTreeSitter::TSNode? = node

    while cur = cursor
      case Noir::TreeSitter.node_type(cur)
      when "call_expression"
        field = field_call_name(cur, source)
        if field
          case field
          when "route"
            args = named_call_args(cur)
            if !args.empty? && (path = string_literal_content(args[0], source))
              full_path = prefix.empty? ? path : nest_join(prefix, path)
              mounts << {"route", full_path} unless mounts.includes?({"route", full_path})
            end
            cursor = chain_receiver(cur)
          when "nest", "nest_service"
            args = named_call_args(cur)
            if !args.empty? && (nest_pfx = string_literal_content(args[0], source))
              full_nest = prefix.empty? ? nest_pfx : nest_join(prefix, nest_pfx)
              mounts << {"nest", full_nest} unless mounts.includes?({"nest", full_nest})
              if args.size >= 2
                collect_router_mounts(args[1], source, file_path, full_nest, visited_fns).each do |m|
                  mounts << m unless mounts.includes?(m)
                end
              end
            end
            cursor = chain_receiver(cur)
          when "merge"
            args = named_call_args(cur)
            if !args.empty?
              collect_router_mounts(args[0], source, file_path, prefix, visited_fns).each do |m|
                mounts << m unless mounts.includes?(m)
              end
            end
            cursor = chain_receiver(cur)
          when "layer", "route_layer", "with_state", "fallback", "fallback_service"
            cursor = chain_receiver(cur)
          else
            cursor = chain_receiver(cur)
          end
        else
          fn_text = call_func_full_text(cur, source)
          if fn_text.ends_with?("Router::new") || fn_text == "new"
            break
          end
          resolve_and_collect_fn_mounts(fn_text, file_path, prefix, visited_fns, mounts)
          break
        end
      when "identifier"
        # A parameter or a binding: only a `let` in scope says what it holds.
        cursor = let_value(cur, Noir::TreeSitter.node_text(cur, source), source)
      else
        break
      end
    end

    mounts
  end

  private def resolve_and_collect_fn_mounts(
    fn_ref : String,
    file_path : String,
    prefix : String,
    visited_fns : Set(String),
    mounts : Array({String, String}),
  )
    entry = lookup_function(fn_ref, file_path) || return
    return if visited_fns.includes?(entry.full_path)
    visited_fns.add(entry.full_path)

    if cached = @fn_mounts_cache[entry.full_path]?
      cached.each do |kind, p|
        full_p = prefix.empty? ? p : nest_join(prefix, p)
        mounts << {kind, full_p} unless mounts.includes?({kind, full_p})
      end
      return
    end

    fn_mounts = [] of {String, String}
    # Only the fn's own body, so a big file is not reparsed once per fn.
    body_source = "fn f() #{entry.body_text}"
    Noir::TreeSitter.parse_rust(body_source) do |root|
      scan_function_body_for_mounts(root, body_source, entry.file_path, visited_fns, fn_mounts)
    end

    @fn_mounts_cache[entry.full_path] = fn_mounts
    fn_mounts.each do |kind, p|
      full_p = prefix.empty? ? p : nest_join(prefix, p)
      mounts << {kind, full_p} unless mounts.includes?({kind, full_p})
    end
  end

  private def scan_function_body_for_mounts(
    body : LibTreeSitter::TSNode,
    source : String,
    file_path : String,
    visited_fns : Set(String),
    mounts : Array({String, String}),
  )
    Noir::TreeSitter.walk(body) do |n|
      next unless Noir::TreeSitter.node_type(n) == "call_expression"
      field = field_call_name(n, source)
      case field
      when "route"
        args = named_call_args(n)
        if !args.empty? && (path = string_literal_content(args[0], source))
          mounts << {"route", path} unless mounts.includes?({"route", path})
        end
      when "nest", "nest_service"
        args = named_call_args(n)
        if !args.empty? && (nest_pfx = string_literal_content(args[0], source))
          mounts << {"nest", nest_pfx} unless mounts.includes?({"nest", nest_pfx})
          if args.size >= 2
            collect_router_mounts(args[1], source, file_path, nest_pfx, visited_fns).each do |m|
              mounts << m unless mounts.includes?(m)
            end
          end
        end
      when "merge"
        args = named_call_args(n)
        if !args.empty?
          collect_router_mounts(args[0], source, file_path, "", visited_fns).each do |m|
            mounts << m unless mounts.includes?(m)
          end
        end
      end
    end
  end

  private def field_call_name(call : LibTreeSitter::TSNode, source : String) : String?
    fn_node = Noir::TreeSitter.field(call, "function")
    return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
    field = Noir::TreeSitter.field(fn_node, "field")
    field ? Noir::TreeSitter.node_text(field, source) : nil
  end

  private def chain_receiver(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    fn_node = Noir::TreeSitter.field(call, "function")
    return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
    Noir::TreeSitter.field(fn_node, "value")
  end

  private def call_func_leaf_name(call : LibTreeSitter::TSNode, source : String) : String?
    fn_node = Noir::TreeSitter.field(call, "function") || return
    text = Noir::TreeSitter.node_text(fn_node, source)
    text.split("::").last.split("<").first.strip
  end

  private def call_func_full_text(call : LibTreeSitter::TSNode, source : String) : String
    fn_node = Noir::TreeSitter.field(call, "function")
    fn_node ? Noir::TreeSitter.node_text(fn_node, source).strip : ""
  end

  private def named_call_args(call : LibTreeSitter::TSNode) : Array(LibTreeSitter::TSNode)
    args = [] of LibTreeSitter::TSNode
    if arg_list = Noir::TreeSitter.field(call, "arguments")
      Noir::TreeSitter.each_named_arg(arg_list) do |arg|
        args << arg
      end
    end
    args
  end

  private def string_literal_content(node : LibTreeSitter::TSNode, source : String) : String?
    return unless Noir::TreeSitter.node_type(node) == "string_literal"
    raw = Noir::TreeSitter.node_text(node, source)
    if raw.starts_with?('"') && raw.ends_with?('"') && raw.size >= 2
      raw[1...-1]
    elsif m = raw.match(/\Ar#*"(.*)"#*\z/m)
      m[1]
    end
  end

  private def nest_join(prefix : String, path : String) : String
    p = prefix.ends_with?('/') ? prefix.rchop('/') : prefix
    s = path.starts_with?('/') ? path : "/#{path}"
    "#{p}#{s}"
  end

  private def scan_actix_scope_middleware(files : Array(String))
    files.each do |file|
      content = read_file(file) || next
      lines = content.split("\n")
      # Stack-based scope tracking for nested Actix-Web scopes
      scope_stack = [] of String

      lines.each_with_index do |line, idx|
        stripped = line.strip

        # Track scope nesting
        scope_match = stripped.match(/web::(?:scope|resource)\s*\(\s*"([^"]*)"/)
        if scope_match
          scope_stack << scope_match[1]
        end

        # Check if this line has auth middleware
        has_auth = false
        middleware_name = "auth"

        MIDDLEWARE_LAYER_PATTERNS.each do |pattern|
          match = stripped.match(pattern)
          if match
            has_auth = true
            middleware_name = match[1]? || "auth"
            break
          end
        end

        if has_auth
          # Determine scope: use stack or walk back to find scope
          current_scope = scope_stack.empty? ? nil : PrefixScope.join_segments(scope_stack)
          if prefix = find_scope_for_line(lines, idx, current_scope)
            @middleware_scopes << {
              prefix:      prefix,
              exact:       false,
              local:       false,
              description: "Protected by Rust #{middleware_name} middleware on #{prefix}",
            }
          end
        end

        # Pop scope on closing parenthesis/brace that ends a scope block
        if stripped == ")" || stripped == ");" || stripped == "})" || stripped == "});"
          scope_stack.pop unless scope_stack.empty?
        end
      end
    end
  end

  private def find_scope_for_line(lines : Array(String), line_idx : Int32, current_scope : String?) : String?
    # Use tracked scope if available
    return current_scope if current_scope

    # Walk backwards to find a scope/route definition
    idx = line_idx - 1
    while idx >= 0 && idx >= line_idx - 10
      prev = lines[idx].strip

      scope_match = prev.match(/web::(?:scope|resource)\s*\(\s*"([^"]*)"/)
      return scope_match[1] if scope_match

      route_match = prev.match(/\.route\s*\(\s*"([^"]*)"/)
      return route_match[1] if route_match

      idx -= 1
    end

    nil
  end

  private def check_endpoint(endpoint : Endpoint)
    if guard = handler_request_guard(endpoint)
      endpoint.add_tag(Tag.new("auth", "Protected by Rust #{guard} request guard", "rust_auth"))
      return
    end

    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?

      line_idx = line_num - 1 # 0-indexed
      next if line_idx < 0 || line_idx >= lines.size

      # Check for guard attributes above the route
      description = check_guard_attributes(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", description, "rust_auth"))
        return
      end

      # Check function signature for auth guard types/extractors
      description = check_function_signature(lines, line_idx, !endpoint.handler.nil?)
      if description
        endpoint.add_tag(Tag.new("auth", description, "rust_auth"))
        return
      end

      # Check for actix-web auth extractors in function body
      description = check_actix_extractors(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", description, "rust_auth"))
        return
      end
    end

    # Check scope-level middleware
    description = check_middleware_scopes(endpoint)
    if description
      endpoint.add_tag(Tag.new("auth", description, "rust_auth"))
    end
  end

  private def check_guard_attributes(lines : Array(String), route_line_idx : Int32) : String?
    # Walk backwards from route attribute to find guard attributes
    idx = route_line_idx - 1
    while idx >= 0 && idx >= route_line_idx - 5
      current = lines[idx].strip
      # Skip empty lines; stop at non-attribute code boundaries
      if current.empty?
        idx -= 1
        next
      end
      break unless current.starts_with?("#[") || current.starts_with?("//")

      if description = guard_attribute_description(current)
        return description
      end

      idx -= 1
    end

    # Attributes stacked below the route attribute guard it just the same.
    annotation_lines_below(lines, route_line_idx, "#[").each do |below|
      if description = guard_attribute_description(below)
        return description
      end
    end

    nil
  end

  private def guard_attribute_description(line : String) : String?
    GUARD_ATTRIBUTE_PATTERNS.each do |pattern|
      if match = line.match(pattern)
        guard_name = match[1]? || "guard"
        return "Protected by Rust #[guard] attribute (#{guard_name})"
      end
    end
    nil
  end

  private def check_function_signature(lines : Array(String), route_line_idx : Int32, handler_resolved : Bool = false) : String?
    # Look at lines after the route attribute for the function signature
    # Route attributes like #[get("/path")] are followed by fn handler(...)
    idx = route_line_idx
    end_idx = [route_line_idx + 5, lines.size - 1].min

    while idx <= end_idx
      current = lines[idx]

      # Check for auth-related types in function parameters
      if current.includes?("fn ") || current.includes?("async fn ")
        # Gather the full function signature (may span multiple lines)
        sig_lines = [current]
        sig_idx = idx + 1
        while sig_idx < lines.size && !current.includes?("{") && !current.includes?("->")
          sig_lines << lines[sig_idx]
          current = lines[sig_idx]
          sig_idx += 1
        end
        signature = sig_lines.join(" ")

        GUARD_TYPE_PATTERNS.each do |pattern|
          signature.scan(pattern) do |match|
            # Its impl was read: it cannot refuse the caller, or it can and
            # `handler_request_guard` already saw it would not here (an
            # `Option<Session>` parameter). Either way the name says nothing.
            verdict = @guard_verdicts[match[0]]?
            next if verdict == false || (verdict && handler_resolved)
            return "Protected by Rust #{match[0]} request guard"
          end
        end

        AXUM_EXTRACTOR_PATTERNS.each do |pattern|
          if signature.matches?(pattern)
            return "Protected by Rust auth extractor"
          end
        end

        break
      end

      idx += 1
    end

    nil
  end

  private def check_actix_extractors(lines : Array(String), route_line_idx : Int32) : String?
    # Check function signature and body for actix-web auth types
    idx = route_line_idx
    end_idx = [route_line_idx + 3, lines.size - 1].min

    while idx <= end_idx
      current = lines[idx]

      ACTIX_AUTH_PATTERNS.each do |pattern|
        if current.matches?(pattern)
          match = current.match(pattern)
          auth_type = match ? match[0] : "auth"
          return "Protected by Actix-Web #{auth_type}"
        end
      end

      idx += 1
    end

    nil
  end

  private def check_middleware_scopes(endpoint : Endpoint) : String?
    url = endpoint.url

    @middleware_scopes.each do |scope|
      prefix = scope[:prefix]
      covered = scope[:exact] ? url == prefix : PrefixScope.prefix_covers?(prefix, url)
      # An Axum layer names router-local paths; that router may itself be
      # `.nest`ed, so `/users` also covers `/api/users`.
      if !covered && scope[:local] && prefix.starts_with?('/') && prefix.size > 1
        covered = url.ends_with?(prefix) || (!scope[:exact] && url.includes?("#{prefix}/"))
      end
      return scope[:description] if covered
    end

    nil
  end
end
