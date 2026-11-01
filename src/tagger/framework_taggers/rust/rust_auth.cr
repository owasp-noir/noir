require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../prefix_scope"
require "../../../miniparsers/rust_request_guards"
require "../../../miniparsers/rust_use_imports"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../utils/c_comments"
require "../../../analyzer/engines/rust_engine"

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
    @middleware_scopes = [] of {prefix: String, exact: Bool, local: Bool, description: String, except: Array({String, Bool}), at: {String, Int32}?}
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
    @app_chains = [] of AppChain
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
    @app_chains.clear
    @rust_type_index = nil
    @auth_verdicts.clear

    files = collect_files_by_extension(".rs")
    build_function_index(files)
    scan_axum_layers(files)
    scan_actix_scope_middleware(files)
    scan_actix_apps(files)
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
                except:      [] of {String, Bool},
                at:          nil,
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
              except:      [] of {String, Bool},
              at:          nil,
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

  # `Condition::new(flag, mw)` / `ConditionEx::from_option(opt)` register the
  # middleware only when something was configured.
  CONDITIONAL_WRAP = /\bCondition\w*\s*::\s*(?:new|from_option)\b/
  # A variable naming the paths a middleware lets through unchecked.
  EXEMPT_VAR = /\b(\w*(?:white|allow|skip|public|exempt|bypass)\w*)\b/i
  # A call that hands the middleware literal paths to pass:
  # `.skip_paths(vec!["/login"])`.
  EXEMPT_CALL    = /\.\w*(?:skip|exclude|allow|ignore|public|whitelist|except)\w*\s*\(((?:[^()]|\((?:[^()]|\([^()]*\))*\))*)\)/i
  CARGO_TOML     = /\ACargo\.toml\z/
  SERVICE_ARG    = /\.service\s*\(\s*((?:\w+::)*\w+)\s*\)/
  SERVICE_TUPLE  = /\.service\s*\(\s*\(([^()]*)\)\s*\)/
  TO_ARG         = /\.to\s*\(\s*((?:\w+::)*\w+)\s*\)/
  CONFIGURE_ARG  = /\.configure\s*\(\s*((?:\w+::)*\w+)\s*\)/
  IMPL_FOR       = /\bimpl\b[^{;]*?\bfor\s+(\w+)[^{;]*\{/
  STRUCT_DECL    = /\bstruct\s+(\w+)/
  TRANSFORM_TYPE = /\btype\s+Transform\s*=\s*(\w+)/
  CALL_FN        = /\bfn\s+call\b[^{;]*\{/
  # The inner service's answer bound to a name (`let res = fut.await?;`,
  # `let res = self.service.call(req).await;`).
  AWAITED_LET = /\blet\s+(?:mut\s+)?\w+\s*(?::[^=;]+)?=\s*(?:fut|future|(?:self\.)?service\.call\([^;]*?\)|next\.run\([^;]*?\))\s*\.await\s*\??\s*;/
  METHOD_TEST = /\bmethod\s*\(\s*\)\s*(!=|==)\s*(?:\w+::)*(\w+)/
  # What a refusing middleware reads from the request to decide.
  CALL_CREDENTIAL = /authoriz|bearer|jwt|token|api[-_]?key|claims|session|login|credential|valid|auth_keys|\bauth\b/i

  # What an auth middleware's own `call` does: the verbs it refuses only some
  # of (`if req.method() != Method::GET && !has_token`).
  record AuthVerdict, only_methods : Array(String), except_methods : Array(String)

  # One `App::new()...` chain: the handlers it registers (nil when they could
  # not be read, then every handler of its crates), the auth middleware it
  # wraps, if any, and where.
  class AppChain
    getter handlers : Set(String)?
    getter crates : Set(String)
    getter file : String
    getter line : Int32
    getter auth : String?
    getter verdict : AuthVerdict?
    getter? conditional : Bool
    getter exempt : Array({String, Bool})
    getter? whitelist_unread : Bool

    def initialize(@handlers, @crates, @file, @line, @auth, @verdict, @conditional, @exempt, @whitelist_unread)
    end

    def serves?(handler : String, crate : String?) : Bool
      return false unless crate && @crates.includes?(crate)
      (names = @handlers).nil? || names.includes?(handler)
    end

    # Whether the middleware refuses this request: not on a path or verb it
    # lets through.
    def guards?(url : String, method : String) : Bool
      return false unless @auth
      return false if @exempt.any? { |(path, by_prefix)| by_prefix ? url.starts_with?(path) : url == path }
      if verdict = @verdict
        return false if verdict.except_methods.includes?(method)
        return false unless verdict.only_methods.empty? || verdict.only_methods.includes?(method)
      end
      true
    end
  end

  # `App::new().wrap(AuthTransform::new(keys, whitelist))` puts the routes
  # registered on that App behind the middleware, bar the paths it lets
  # through. Each chain is its own scope: a second App of the same crate
  # (qdrant's metrics server) does not inherit the wrap.
  private def scan_actix_apps(files : Array(String))
    files.each do |file|
      relative = base_relative_path(file)
      next if Analyzer::Rust::RustEngine.test_path?(relative) || relative.includes?("/examples/")
      content = read_file(file) || next
      next unless content.includes?("App::new")

      begin
        test_regions = Analyzer::Rust::RustEngine.collect_cfg_test_regions(content)
        crate = nearest_project_root(file, CARGO_TOML)
        Noir::TreeSitter.parse_rust(content) do |root|
          Noir::TreeSitter.walk(root) do |node|
            next unless Noir::TreeSitter.node_type(node) == "call_expression"
            next unless call_func_full_text(node, content).ends_with?("App::new")
            start = LibTreeSitter.ts_node_start_byte(node).to_i
            next if test_regions.any? { |(from, to)| start >= from && start < to }
            record_app_chain(node, content, file, crate)
          end
        end
      rescue e
        @logger.debug "actix app scan error in #{file}: #{e}"
      end
    end
  end

  private def record_app_chain(root_call : LibTreeSitter::TSNode, content : String, file : String, crate : String?)
    top = root_call
    while (field = Noir::TreeSitter.parent(top)) && Noir::TreeSitter.node_type(field) == "field_expression"
      outer = Noir::TreeSitter.parent(field) || break
      break unless Noir::TreeSitter.node_type(outer) == "call_expression"
      function = Noir::TreeSitter.field(outer, "function") || break
      break unless LibTreeSitter.ts_node_start_byte(function) == LibTreeSitter.ts_node_start_byte(field) &&
                   LibTreeSitter.ts_node_end_byte(function) == LibTreeSitter.ts_node_end_byte(field)
      top = outer
    end

    chain_text = Noir::CComments.strip(Noir::TreeSitter.node_text(top, content))
    crates = Set(String).new
    crates << crate if crate
    handlers = Set(String).new
    collect_registered_handlers(chain_text, file, handlers, crates, 0)

    auth = nil
    verdict = nil
    conditional = false
    exempt = [] of {String, Bool}
    unread = false
    line = content.byte_slice(0, LibTreeSitter.ts_node_start_byte(top).to_i).count('\n') + 1
    Noir::TreeSitter.walk(top) do |node|
      next if auth
      next unless Noir::TreeSitter.node_type(node) == "call_expression" && field_call_name(node, content) == "wrap"
      next unless wrap_on_chain?(node, content, root_call)
      arg = named_call_args(node)[0]? || next
      type = wrapped_type_names(arg, content).find { |name| name.matches?(/Auth/) && !name.matches?(CSRF_NAME) }
      type || next
      found = auth_middleware_verdict(type)
      next unless found
      auth = type
      verdict = found[0]
      text = Noir::CComments.strip(Noir::TreeSitter.node_text(arg, content))
      conditional = text.matches?(CONDITIONAL_WRAP)
      exempt = exempt_paths(text, enclosing_fn_text(node, content))
      inline = [] of {String, Bool}
      text.scan(EXEMPT_CALL) { |call| call[1].scan(/"(\/[^"]*)"/) { |literal| inline << {literal[1], false} } }
      exempt.concat(inline)
      unread = exempt.empty? && text.matches?(EXEMPT_VAR)
      line = content.byte_slice(0, wrap_byte(node)).count('\n') + 1
    end

    return if auth.nil? && handlers.empty?
    @app_chains << AppChain.new(handlers.empty? ? nil : handlers, crates, file, line, auth, verdict, conditional, exempt, unread)
  end

  # The handler fns a chain registers: `.service(f)`, `.route("/p", .. .to(f))`
  # and, through `.configure(g)`, whatever `g` registers on its `cfg`.
  private def collect_registered_handlers(text : String, file : String, handlers : Set(String), crates : Set(String), depth : Int32)
    text.scan(SERVICE_ARG) { |m| handlers << m[1].split("::").last }
    text.scan(SERVICE_TUPLE) { |m| m[1].split(',').each { |name| handlers << name.strip.split("::").last unless name.strip.empty? } }
    text.scan(TO_ARG) { |m| handlers << m[1].split("::").last }
    return if depth > 4
    text.scan(CONFIGURE_ARG) do |m|
      entry = lookup_function(m[1], file) || next
      crate = nearest_project_root(entry.file_path, CARGO_TOML)
      crates << crate if crate
      collect_registered_handlers(Noir::CComments.strip(entry.body_text), entry.file_path, handlers, crates, depth + 1)
    end
  end

  # Byte offset of the `wrap` in `chain.wrap(..)`, so a multi-line chain
  # reports the line of the registration, not the line the chain starts on.
  private def wrap_byte(call : LibTreeSitter::TSNode) : Int32
    field = Noir::TreeSitter.field(call, "function").try { |fn| Noir::TreeSitter.field(fn, "field") }
    LibTreeSitter.ts_node_start_byte(field || call).to_i
  end

  # Whether `.wrap` sits on the chain that starts at `root_call`.
  private def wrap_on_chain?(call : LibTreeSitter::TSNode, source : String, root_call : LibTreeSitter::TSNode) : Bool
    node = call
    while recv = chain_receiver(node)
      return false unless Noir::TreeSitter.node_type(recv) == "call_expression"
      node = recv
    end
    LibTreeSitter.ts_node_start_byte(node) == LibTreeSitter.ts_node_start_byte(root_call)
  end

  # The types a wrapped expression constructs: the `Type` of `Type::new(..)`
  # and of `Type { .. }`, found in the syntax tree, so a string literal or a
  # header name that merely says "Auth" is never one.
  private def wrapped_type_names(arg : LibTreeSitter::TSNode, source : String) : Array(String)
    names = [] of String
    Noir::TreeSitter.walk(arg) do |node|
      case Noir::TreeSitter.node_type(node)
      when "call_expression"
        segments = call_func_full_text(node, source).split("::")
        names << (segments.size >= 2 ? segments[-2] : segments.last).split('<').first.strip
      when "struct_expression"
        name = Noir::TreeSitter.field(node, "name").try { |n| Noir::TreeSitter.node_text(n, source) }
        names << name.split("::").last if name
      end
    end
    names.select(&.matches?(/\A[A-Z]\w*\z/))
  end

  private def enclosing_fn_text(node : LibTreeSitter::TSNode, source : String) : String
    current = node
    while parent = Noir::TreeSitter.parent(current)
      return Noir::CComments.strip(Noir::TreeSitter.node_text(parent, source)) if Noir::TreeSitter.node_type(parent) == "function_item"
      current = parent
    end
    Noir::CComments.strip(source)
  end

  # `{struct names, impl blocks by implementing type}` of the non-test sources,
  # read once.
  private def rust_type_index : Tuple(Set(String), Hash(String, Array(String)))
    @rust_type_index ||= begin
      structs = Set(String).new
      impls = Hash(String, Array(String)).new
      collect_files_by_extension(".rs").each do |file|
        next if Analyzer::Rust::RustEngine.test_path?(base_relative_path(file))
        content = read_file(file) || next
        next unless content.includes?("struct ") || content.includes?("impl")
        code = Noir::CComments.strip(content)
        code.scan(STRUCT_DECL) { |m| structs << m[1] }
        code.scan(IMPL_FOR) do |m|
          open = m.byte_end(0) - 1
          close = matching_brace(code, open) || next
          (impls[m[1]] ||= [] of String) << code.byte_slice(open, close - open + 1)
        end
      end
      {structs, impls}
    end
  end

  @rust_type_index : Tuple(Set(String), Hash(String, Array(String)))?
  @auth_verdicts = Hash(String, Tuple(AuthVerdict)?).new

  # Byte index of the `}` closing the `{` at `open`.
  private def matching_brace(code : String, open : Int) : Int32?
    depth = 0
    bytes = code.to_slice
    index = open
    while index < bytes.size
      case bytes[index]
      when '{'.ord then depth += 1
      when '}'.ord
        depth -= 1
        return index if depth == 0
      end
      index += 1
    end
  end

  # Whether `type` is an auth middleware, judged by its own `call` (and that of
  # the service its `Transform` builds): it must answer 401/403 for a request
  # without credentials, before the inner service has answered. A type the
  # scan does not declare is trusted by its name. Cached per type.
  private def auth_middleware_verdict(type : String) : Tuple(AuthVerdict)?
    return @auth_verdicts[type] if @auth_verdicts.has_key?(type)
    @auth_verdicts[type] = judge_auth_type(type)
  end

  private def judge_auth_type(type : String) : Tuple(AuthVerdict)?
    structs, impls = rust_type_index
    return {AuthVerdict.new([] of String, [] of String)} unless structs.includes?(type) || impls.has_key?(type)

    blocks = (impls[type]? || [] of String).dup
    blocks.dup.each do |block|
      block.match(TRANSFORM_TYPE).try { |m| blocks.concat(impls[m[1]]? || [] of String) }
    end
    blocks.each do |block|
      block.scan(CALL_FN) do |m|
        open = m.byte_end(0) - 1
        close = matching_brace(block, open) || next
        verdict = judge_call_body(block.byte_slice(open, close - open + 1))
        return {verdict} if verdict
      end
    end
    nil
  end

  private def judge_call_body(body : String) : AuthVerdict?
    # A refusal read off the response the inner service already gave
    # (`let res = fut.await; if res.status() == ..`) refuses no caller.
    code = body.match(AWAITED_LET).try { |awaited| body[0, awaited.begin] } || body
    return unless code.gsub(COMPARED, "").matches?(MIDDLEWARE_REFUSAL) && code.matches?(CALL_CREDENTIAL)
    only = [] of String
    except = [] of String
    code.scan(METHOD_TEST) do |m|
      verb = m[2].upcase
      (m[1] == "!=" ? except : only) << verb
    end
    AuthVerdict.new(only.uniq!, except.uniq!)
  end

  # Paths the wrapped middleware lets through: the `exact("/x")` / `prefix("/x")`
  # entries (or plain `"/x"` literals of a whitelist-named variable) of a
  # variable handed to it, read from where that variable is built in the same
  # fn (`let mut w = vec![..]`, `w.push(..)`).
  private def exempt_paths(wrap_text : String, scope_text : String) : Array({String, Bool})
    paths = [] of {String, Bool}
    wrap_text.scan(/\b[a-z_]\w*\b/) do |var|
      name = Regex.escape(var[0])
      listed = var[0].matches?(EXEMPT_VAR)
      scope_text.scan(/\blet\s+(?:mut\s+)?#{name}\b[^;]*;|\b#{name}\s*\.\s*(?:push|extend)\s*\([^;]*;/m) do |stmt|
        stmt[0].scan(/(\w*)\s*\(\s*"(\/[^"]*)"\s*\)/) do |entry|
          by_prefix = entry[1].downcase.includes?("prefix")
          paths << {entry[2], by_prefix} if by_prefix || entry[1].downcase.includes?("exact")
        end
        stmt[0].scan(/(?<![\w(])"(\/[^"]*)"/) { |entry| paths << {entry[1], false} } if listed
      end
    end
    paths.uniq!
  end

  # The tag an endpoint gets from the App chains that serve it: guarded when
  # one of them wraps an auth middleware that refuses it; the description says
  # when another chain serves the same handler without it, or when the
  # middleware is only registered under a setting.
  private def app_chain_tag(endpoint : Endpoint) : Tag?
    handler = endpoint.handler || return
    path = handler.path || return
    name = handler.name.split(/::|\./).last
    crate = nearest_project_root(path, CARGO_TOML)
    serving = @app_chains.select(&.serves?(name, crate))
    guarded = serving.find(&.guards?(endpoint.url, endpoint.method))
    return unless guarded
    notes = [] of String
    notes << "registered only when auth keys are configured; unauthenticated when none are" if guarded.conditional?
    notes << "its whitelisted paths could not be read" if guarded.whitelist_unread?
    notes << "the App's routes could not be resolved; applies to its whole crate" if guarded.handlers.nil?
    others = serving.reject(&.guards?(endpoint.url, endpoint.method))
    # Served by an App without the wrap too (qdrant's metrics port): that is
    # open attack surface, so it is no guard; only a note says the main App
    # wraps it.
    unless others.empty?
      where = "#{base_relative_path(others.first.file).lchop('/')}:#{others.first.line}"
      return Tag.new("auth_partial", "Wrapped by Rust #{guarded.auth} middleware on one App, but also served without it by another App (#{where})", "rust_app_scope", guarded.file, guarded.line)
    end
    notes << "refuses only some verbs" if (v = guarded.verdict) && (!v.only_methods.empty? || !v.except_methods.empty?)
    Tag.new("auth", "Protected by Rust #{guarded.auth} middleware on its App" + (notes.empty? ? "" : " (#{notes.join("; ")})"), "rust_auth", guarded.file, guarded.line)
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
    if scope = middleware_scope_for(endpoint)
      at = scope[:at]
      endpoint.add_tag(Tag.new("auth", scope[:description], "rust_auth", at.try(&.[0]), at.try(&.[1])))
    end

    if tag = app_chain_tag(endpoint)
      endpoint.add_tag(tag)
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

  private def middleware_scope_for(endpoint : Endpoint)
    url = endpoint.url

    @middleware_scopes.each do |scope|
      prefix = scope[:prefix]
      next if scope[:except].any? { |(path, by_prefix)| by_prefix ? url.starts_with?(path) : url == path }
      covered = scope[:exact] ? url == prefix : PrefixScope.prefix_covers?(prefix, url)
      # An Axum layer names router-local paths; that router may itself be
      # `.nest`ed, so `/users` also covers `/api/users`.
      if !covered && scope[:local] && prefix.starts_with?('/') && prefix.size > 1
        covered = url.ends_with?(prefix) || (!scope[:exact] && url.includes?("#{prefix}/"))
      end
      return scope if covered
    end

    nil
  end
end
