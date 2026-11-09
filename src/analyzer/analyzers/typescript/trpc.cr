require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"
require "../../../miniparsers/js_handler_resolver"
require "../../../utils/top_level_split"
require "../../../utils/char_offsets"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/extraction_result_cache"

module Analyzer::Typescript
  class TRPC < Analyzer::Javascript::JavascriptEngine
    analyzer_for "ts_trpc"

    DEFAULT_PREFIX = "/api/trpc"
    alias RouterKey = Tuple(String, String)

    record TRPCProcedureData,
      method : String,
      line : Int32,
      file : String,
      chain_text : String,
      params : Array(Param),
      callees : Array(Noir::JSCalleeExtractor::Entry),
      handler : Handler,
      auth_tag : Tag?

    record TRPCRouterEntry,
      key : String,
      line : Int32,
      kind : Symbol, # :identifier, :nested_router, :procedure
      ident : String,
      nested_entries : Array(TRPCRouterEntry),
      proc : TRPCProcedureData?

    record Router,
      base_path : String,
      name : String,
      entries : Array(TRPCRouterEntry),
      file : String,
      line : Int32

    # A procedure exported as a standalone `const` and referenced by name
    # inside a router map.
    record Procedure,
      base_path : String,
      name : String,
      proc : TRPCProcedureData

    # A Next.js pages-router mount (`pages/api/trpc/slots/[trpc].ts` handing
    # `slotsRouter` to `createNextApiHandler`): the router's procedure paths
    # are served under the mount's directory, `/api/trpc/slots/getSchedule`.
    # `specifier` is where the router was imported from, which tells two
    # same-named routers apart.
    record Mount,
      base_path : String,
      prefix : String,
      router : String,
      specifier : String?,
      file : String,
      line : Int32

    record TRPCFileFacts,
      routers : Array(Router),
      procedures : Array(Procedure),
      mount : Mount?,
      url_prefix : String?,
      builder_defs : Hash(String, String)

    TAGGER = "trpc_auth"

    # Procedure builders and middleware (`authedProcedure = t.procedure
    # .use(isAuthed)`, `isAuthed = t.middleware(...)`), by name, so a
    # procedure's auth is read from the definitions its builder stacks.
    @builder_defs = Hash(String, String).new
    @named_procedures = Hash(String, Array(Procedure)).new

    @@memo = Hash(UInt64, TRPCFileFacts).new
    @@memo_mutex = Mutex.new

    Noir::ExtractionResultCache.register_clearer do
      @@memo_mutex.synchronize { @@memo.clear }
    end

    private def trpc_file_facts(path : String, content : String, base_path : String, include_callees : Bool) : TRPCFileFacts
      key = Noir::ExtractionResultCache.key(content, "trpc_facts", path, base_path, include_callees ? "1" : "0")
      Noir::ExtractionResultCache.fetch(@@memo, key, @@memo_mutex) do
        extract_trpc_facts(path, content, base_path, include_callees)
      end
    end

    def analyze
      result = [] of Endpoint
      routers = Hash(RouterKey, Router).new
      all_routers = [] of Router
      procedures = Hash(RouterKey, Procedure).new
      procedures_by_name = Hash(String, Procedure).new
      url_prefixes = Hash(String, String).new
      mounts = [] of Mount
      include_callee = callees_needed?

      # Merged in file order, not worker-completion order: two apps that name
      # the same router or procedure leave the later file's in place, so the
      # order decides which wins (see `Analyzer#ordered_scan_files`).
      per_file = ordered_scan_files(get_files_by_extensions([".js", ".ts", ".jsx", ".tsx", ".cts", ".mts", ".cjs", ".mjs"])) do |path|
        next if trpc_test_fixture_path?(path)

        raw = read_file_content(path)
        base_path = configured_base_for(path)
        mount = next_mount(path, raw, base_path)
        content = Noir::JSRouteExtractor.strip_js_comments(raw)
        defs = extract_builder_defs(content, path)
        none = {[] of Router, [] of Procedure, base_path, nil.as(String?), mount, defs}
        next none unless trpc_candidate?(raw)
        next none if Noir::JSRouteExtractor.test_stub_only?(path, raw, include_client_frameworks: false)
        next none unless trpc_candidate?(content)

        facts = trpc_file_facts(path, content, base_path, include_callee)
        all_defs = defs.dup
        all_defs.merge!(facts.builder_defs)
        {facts.routers, facts.procedures, base_path, facts.url_prefix, mount || facts.mount, all_defs}
      rescue e
        logger.debug "Error analyzing tRPC file #{path}: #{e.message}"
        nil
      end

      per_file.each do |collected, collected_procs, base_path, found, mount, defs|
        collected.each { |r| routers[router_key(r)] = r }
        all_routers.concat(collected)
        collected_procs.each do |p|
          procedures[router_key(p.base_path, p.name)] = p
          procedures_by_name[p.name] = p
          (@named_procedures[p.name] ||= [] of Procedure) << p
        end
        url_prefixes[base_path] = found if found
        mounts << mount if mount
        @builder_defs.merge!(defs)
      end

      # Each mount serves its own router's subtree. A root that is not
      # mounted is flattened at the configured prefix as before, minus the
      # mounted routers inside it, whose URLs are the mount's.
      mounted = Set(RouterKey).new
      mounts.each do |mount|
        if router = mounted_router(mount, all_routers)
          flatten_router(router, "", routers, procedures, procedures_by_name, mount.prefix, result, Set(RouterKey).new)
          mounted << router_key(router)
        else
          # The router lives outside the scan; the mount still answers.
          {"GET", "POST"}.each do |verb|
            endpoint = Endpoint.new("#{mount.prefix.chomp('/')}/{trpc}", verb)
            endpoint.details = Details.new(PathInfo.new(mount.file, mount.line))
            endpoint.push_param(Param.new("trpc", "", "path"))
            result << endpoint
          end
        end
      end

      return result if routers.empty?

      used_as_child = Set(RouterKey).new
      routers.each_value do |router|
        router.entries.each do |entry|
          if entry.kind == :identifier
            child_key = router_key(router.base_path, entry.ident)
            used_as_child.add(child_key) if routers.has_key?(child_key)
          end
        end
      end

      roots = routers.values.reject { |r| used_as_child.includes?(router_key(r)) }
      roots = routers.values if roots.empty?

      roots.each do |root|
        next if mounted.includes?(router_key(root))
        url_prefix = url_prefixes[root.base_path]? || DEFAULT_PREFIX
        flatten_router(root, "", routers, procedures, procedures_by_name, url_prefix, result, mounted.dup)
      end

      result
    end

    NEXT_MOUNT_ROUTER_RE = /createNextApiHandler\s*\(\s*(?:\{[^}]*?\brouter\s*:\s*)?([A-Za-z_$][\w$]*)/

    private def next_mount(path : String, raw : String, base_path : String) : Mount?
      return unless Noir::JSRouteExtractor.trpc_next_mount?(path, raw)
      content = Noir::JSRouteExtractor.strip_js_comments(raw)
      m = content.match(NEXT_MOUNT_ROUTER_RE) || return
      scoped = Noir::PathScope.base_relative(path, base_path)
      pages = scoped.index("/pages/") || return
      prefix = extract_prefix(content, string_literal_mask(content)) ||
               scoped[(pages + "/pages".size)...(scoped.rindex('/') || scoped.size)]
      local = m[1]
      specifier, exported = Noir::JSHandlerResolver.imports_of(content, path)[local]? || {nil, nil}
      Mount.new(base_path, prefix.empty? ? "/" : prefix, exported || local, specifier, path, line_number_for_index(content, m.begin(0)))
    end

    # The mounted router among those named alike: the one whose file the
    # mount's import specifier names (`.../viewer/eventTypes/heavy/_router`
    # beside `.../viewer/eventTypes/_router`), by trailing path segments,
    # so a workspace alias (`@calcom/trpc/server/...`) matches too.
    private def mounted_router(mount : Mount, all_routers : Array(Router)) : Router?
      all_routers.select { |r| r.base_path == mount.base_path && r.name == mount.router }
        .max_by? { |router| specifier_score(mount.specifier, mount.file, router.file) }
    end

    # `get` that a router imports from `./procedures/get`, among the
    # procedures named alike across the scan.
    private def imported_procedure(ident : String, router_file : String, base_path : String) : Procedure?
      specifier, exported = Noir::JSHandlerResolver.imports_of(read_file_content(router_file), router_file)[ident]? || return
      @named_procedures[exported || ident]?.try &.select { |p| p.base_path == base_path }
        .max_by? { |p| specifier_score(specifier, router_file, p.proc.file) }
    end

    # Trailing path segments `specifier` (as imported by `importer`) shares
    # with `file`; a relative one is joined to the importer's directory first.
    private def specifier_score(specifier : String?, importer : String, file : String) : Int32
      return 0 unless specifier
      spec = specifier.starts_with?('.') ? Path[importer].parent.join(specifier).normalize.to_posix.to_s : specifier
      spec = spec.sub(/\.[cm]?[jt]sx?\z/, "").split('/').reverse!
      target = Path[file].normalize.to_posix.to_s.sub(/\.[^.\/]+\z/, "").chomp("/index").split('/').reverse!
      spec.zip?(target).take_while { |a, b| a == b }.size
    end

    PROCEDURE_HINTS = [
      ".query(",
      ".query (",
      ".mutation(",
      ".mutation (",
      ".subscription(",
      ".subscription (",
    ]
    PROCEDURE_HINTS_RE = Regex.union(PROCEDURE_HINTS)

    PREFIX_HINTS = [
      "endpoint:",
      "createExpressMiddleware",
      "createKoaMiddleware",
      "fastifyTRPCPlugin",
      "fastifyTRPC",
    ]
    PREFIX_HINTS_RE = Regex.union(PREFIX_HINTS)

    V9_MERGE_HINTS = [
      ".merge(",
      ".merge (",
    ]
    V9_MERGE_HINTS_RE = Regex.union(V9_MERGE_HINTS)

    TRPC_ROOT_MARKER_RE  = Regex.union("initTRPC", "createTRPCRouter")
    TRPC_MENTION_RE      = /trpc/i
    V9_ROUTER_MARKER_RE  = Regex.union("createRouter", "trpc.router", ".router")
    PROCEDURE_BUILDER_RE = Regex.union("Procedure", ".procedure")

    private def trpc_candidate?(content : String) : Bool
      content.matches?(/endpoint\s*:/) ||
        content.matches?(PREFIX_HINTS_RE) ||
        content.matches?(TRPC_ROOT_MARKER_RE) ||
        (content.includes?("router(") && trpc_router_import?(content)) ||
        v9_router_candidate?(content) ||
        (procedure_builder?(content) && content.matches?(PROCEDURE_HINTS_RE))
    end

    private def v9_router_candidate?(content : String) : Bool
      return false unless content.matches?(V9_ROUTER_MARKER_RE)
      content.matches?(V9_MERGE_HINTS_RE) || content.matches?(PROCEDURE_HINTS_RE)
    end

    private def procedure_builder?(content : String) : Bool
      content.matches?(PROCEDURE_BUILDER_RE)
    end

    private def trpc_router_import?(content : String) : Bool
      content.matches?(/import\b[^;]*\brouter\b[^;]*from\s*['"][^'"]*trpc[^'"]*['"]/)
    end

    TEST_FIXTURE_PATH_MARKERS = [
      "/test/",
      "/tests/",
      "/__tests__/",
      "/e2e/",
      "/snapshots/",
      "/test-files/",
    ]

    private def trpc_test_fixture_path?(path : String) : Bool
      relative = base_relative_path(path)
      TEST_FIXTURE_PATH_MARKERS.any? { |marker| relative.includes?(marker) } ||
        relative.includes?(".test.") ||
        relative.includes?(".spec.")
    end

    private def router_key(router : Router) : RouterKey
      router_key(router.base_path, router.name)
    end

    private def router_key(base_path : String, name : String) : RouterKey
      {base_path, name}
    end

    private def extract_prefix(content : String, literal_mask : Array(Bool)) : String?
      if content_matches?(content, TRPC_MENTION_RE)
        content.scan(/endpoint\s*:\s*['"`]([^'"`]+)['"`]/) do |m|
          next if literal_position?(literal_mask, m.byte_begin(0))
          next if m[1].includes?("${")
          next unless m[1].starts_with?('/')
          return m[1]
        end
      end

      content.scan(/\.\s*use\s*\(\s*['"`]([^'"`]+)['"`]\s*,\s*[^)]*?(?:trpcExpress\.createExpressMiddleware|createExpressMiddleware|createKoaMiddleware)/m) do |m|
        next if literal_position?(literal_mask, m.byte_begin(0))
        return m[1]
      end

      content.scan(/(?:fastifyTRPCPlugin|fastifyTRPC)\b[^)]*?prefix\s*:\s*['"`]([^'"`]+)['"`]/m) do |m|
        next if literal_position?(literal_mask, m.byte_begin(0))
        return m[1]
      end

      nil
    end

    PROCEDURE_VERBS = {"query" => "GET", "mutation" => "POST", "subscription" => "SUBSCRIBE"}

    private def flatten_router(router : Router, prefix_dotted : String,
                               routers : Hash(RouterKey, Router),
                               procedures : Hash(RouterKey, Procedure),
                               procedures_by_name : Hash(String, Procedure),
                               url_prefix : String,
                               result : Array(Endpoint),
                               visited : Set(RouterKey))
      current_key = router_key(router)
      return if visited.includes?(current_key)
      visited.add(current_key)

      flatten_entries(router.entries, prefix_dotted, router.base_path, router.file, router.line,
        routers, procedures, procedures_by_name, url_prefix, result, visited)

      visited.delete(current_key)
    end

    private def flatten_entries(entries : Array(TRPCRouterEntry), prefix_dotted : String,
                                base_path : String, file : String, base_line : Int32,
                                routers : Hash(RouterKey, Router),
                                procedures : Hash(RouterKey, Procedure),
                                procedures_by_name : Hash(String, Procedure),
                                url_prefix : String,
                                result : Array(Endpoint),
                                visited : Set(RouterKey))
      base = url_prefix.empty? ? "/" : url_prefix.chomp('/')

      entries.each do |entry|
        child_prefix = prefix_dotted.empty? ? entry.key : "#{prefix_dotted}.#{entry.key}"

        case entry.kind
        when :identifier
          ident = entry.ident
          if child = routers[router_key(base_path, ident)]?
            flatten_router(child, child_prefix, routers, procedures, procedures_by_name, url_prefix, result, visited)
            next
          end

          if proc = imported_procedure(ident, file, base_path) || procedures[router_key(base_path, ident)]? || procedures_by_name[ident]?
            emit_procedure_data(proc.proc, "#{base}/#{child_prefix}", result)
            next
          end
        when :nested_router
          flatten_entries(entry.nested_entries, child_prefix, base_path, file, entry.line,
            routers, procedures, procedures_by_name, url_prefix, result, visited)
        when :procedure
          if pdata = entry.proc
            emit_procedure_data(pdata, "#{base}/#{child_prefix}", result)
          end
        end
      end
    end

    private def emit_procedure_data(proc : TRPCProcedureData, url : String, result : Array(Endpoint))
      endpoint = Endpoint.new(url, proc.method)
      endpoint.details = Details.new(PathInfo.new(proc.file, proc.line))
      proc.params.each { |p| endpoint.push_param(p) }
      attach_js_callees(endpoint, proc.callees)
      endpoint.handler = proc.handler.name.empty? ? Handler.new(url.split('/').last, proc.file, proc.line) : proc.handler
      if tag = proc.auth_tag || procedure_auth_tag(proc.chain_text)
        endpoint.add_tag(tag)
      end
      result << endpoint
    end

    DYNAMIC_IMPORT_RE   = /\bimport\s*\(\s*['"`]([^'"`]+)['"`]\s*\)/
    IMPORTED_EXPORT_RES = [
      /\{\s*([\w$]+)(?:\s*:\s*[\w$]+)?\s*\}\s*=\s*await\s+import\s*\(/,
      /\(\s*await\s+import\s*\([^()]*\)\s*\)\s*\.\s*([\w$]+)/,
      /import\s*\([^()]*\)\s*\.\s*then\s*\(\s*\(?\s*([\w$]+)\s*\)?\s*=>\s*\1\s*\.\s*([\w$]+)/,
    ]
    RESOLVER_CALL_RE = /(?:\A\s*|\breturn\s+)(?:await\s+)?([A-Za-z_$][\w$]*)\s*\(/

    private def procedure_handler(body : String, file : String, line : Int32, name : String) : Handler
      unless body.empty?
        specs = body.scan(DYNAMIC_IMPORT_RE).map(&.[1]).uniq!
        handler = if specs.size == 1
                    export = IMPORTED_EXPORT_RES.compact_map { |re| body.match(re).try { |m| m[m.size - 1] } }.first?
                    Noir::JSHandlerResolver.resolve_module_export(specs[0], export, file)
                  elsif specs.empty? && (call = body.match(RESOLVER_CALL_RE))
                    Noir::JSHandlerResolver.resolve(call[1], read_file_content(file), file)
                  end
        return handler if handler && handler.path
      end
      Handler.new(name, file, line)
    rescue
      Handler.new(name, file, line)
    end

    AUTH_ERROR_RE     = /\bTRPCError\s*\(\s*\{[^{}]*?\bcode\s*:\s*['"`](?:UNAUTHORIZED|FORBIDDEN)['"`]/
    BUILDER_REF_RE    = /(?<![\w$.])[A-Za-z_$][\w$]*\b/
    USE_REF_RE        = /\.\s*(?:use|unstable_pipe|pipe|concat)\s*\(\s*([A-Za-z_$][\w$]*)\s*\)/
    BASE_PROCEDURE_RE = /\.\s*procedure\b/

    private def procedure_auth_tag(chain : String) : Tag?
      head = chain[/\A\s*([A-Za-z_$][\w$]*)/, 1]? || return
      read = [] of String
      guard = chain.matches?(AUTH_ERROR_RE) ? "inline middleware" : builder_guard(chain, read, Set(String).new)
      if guard
        Tag.new("auth", guard == head ? "Protected by tRPC #{head}" : "Protected by tRPC #{head} (#{guard})", TAGGER)
      elsif read.any?(&.matches?(BASE_PROCEDURE_RE)) &&
            read.all? { |text| text.scan(USE_REF_RE).all? { |m| @builder_defs.has_key?(m[1]) } }
        Tag.new("anonymous", "tRPC #{head} admits anonymous callers", TAGGER)
      end
    end

    private def builder_guard(text : String, read : Array(String), seen : Set(String)) : String?
      read << text
      text.scan(BUILDER_REF_RE) do |m|
        definition = @builder_defs[m[0]]? || next
        next unless seen.add?(m[0])
        return m[0] if definition.matches?(AUTH_ERROR_RE)
        if found = builder_guard(definition, read, seen)
          return found
        end
      end
      nil
    end

    BUILDER_DEF_HINT_RE = /\.\s*(?:use|unstable_pipe|procedure)\b|\bmiddleware\s*\(|\bTRPCError\b/

    private def extract_builder_defs(source : String, path : String) : Hash(String, String)
      defs = Hash(String, String).new
      return defs unless content_matches?(source, TRPC_MENTION_RE) && source.matches?(BUILDER_DEF_HINT_RE)

      Noir::TreeSitter.parse_js_family(source, path) do |root|
        Noir::TreeSitter.walk(root) do |node|
          case Noir::TreeSitter.node_type(node)
          when "variable_declarator"
            vd_name = Noir::TreeSitter.field(node, "name")
            vd_val = Noir::TreeSitter.field(node, "value")
            if vd_name && vd_val && Noir::TreeSitter.node_type(vd_name) == "identifier"
              val_u = Noir::TreeSitter.unwrap_expression(vd_val)
              val_text = Noir::TreeSitter.node_text(val_u, source)
              if val_text.matches?(BUILDER_DEF_HINT_RE)
                name = Noir::TreeSitter.node_text(vd_name, source)
                defs[name] = val_text
              end
            end
          when "function_declaration"
            if fn_name = Noir::TreeSitter.field(node, "name")
              fn_text = Noir::TreeSitter.node_text(node, source)
              if fn_text.matches?(BUILDER_DEF_HINT_RE)
                name = Noir::TreeSitter.node_text(fn_name, source)
                defs[name] = fn_text
              end
            end
          end
        end
      end
      defs
    end

    private def normalize_v9_merge_prefix(prefix : String?, child : String) : String
      raw = prefix || child
      raw.strip.gsub(/\A\.+|\.+\z/, "")
    end

    private def extract_trpc_facts(path : String, source : String, base_path : String, include_callees : Bool) : TRPCFileFacts
      routers = [] of Router
      procedures = [] of Procedure
      builder_defs = Hash(String, String).new
      mount = next_mount(path, source, base_path)
      literal_mask = string_literal_mask(source)
      url_prefix = extract_prefix(source, literal_mask)

      Noir::TreeSitter.parse_js_family(source, path) do |root|
        object_decls = Hash(String, Tuple(LibTreeSitter::TSNode, Int32)).new
        pending_router_args = [] of Tuple(String, String, Int32)

        Noir::TreeSitter.walk(root) do |node|
          case Noir::TreeSitter.node_type(node)
          when "variable_declarator"
            vd_name = Noir::TreeSitter.field(node, "name")
            vd_val = Noir::TreeSitter.field(node, "value")
            if vd_name && vd_val && Noir::TreeSitter.node_type(vd_name) == "identifier"
              name = Noir::TreeSitter.node_text(vd_name, source)
              val_u = Noir::TreeSitter.unwrap_expression(vd_val)
              line = Noir::TreeSitter.node_start_row(node) + 1

              val_text = Noir::TreeSitter.node_text(val_u, source)
              if val_text.matches?(BUILDER_DEF_HINT_RE)
                builder_defs[name] = val_text
              end

              if Noir::TreeSitter.node_type(val_u) == "object"
                object_decls[name] = {val_u, line}
              end

              if router_call_node?(val_u, source)
                if args_node = Noir::TreeSitter.field(val_u, "arguments")
                  if arg0 = Noir::TreeSitter.first_named_arg(args_node)
                    arg0_u = Noir::TreeSitter.unwrap_expression(arg0)
                    case Noir::TreeSitter.node_type(arg0_u)
                    when "object"
                      entries = extract_router_entries(arg0_u, source, path, base_path, include_callees)
                      routers << Router.new(base_path, name, entries, path, line)
                    when "identifier"
                      target_ident = Noir::TreeSitter.node_text(arg0_u, source)
                      pending_router_args << {name, target_ident, line}
                    end
                  end
                end
              elsif v9_chain_router?(val_u, source)
                entries = extract_v9_chain_entries(val_u, source, path, base_path, include_callees)
                routers << Router.new(base_path, name, entries, path, line)
              elsif procedure_chain?(val_u, source)
                proc_data = extract_procedure_data(val_u, source, path, include_callees)
                procedures << Procedure.new(base_path, name, proc_data)
              end
            end
          when "function_declaration"
            if fn_name = Noir::TreeSitter.field(node, "name")
              fn_text = Noir::TreeSitter.node_text(node, source)
              if fn_text.matches?(BUILDER_DEF_HINT_RE)
                name = Noir::TreeSitter.node_text(fn_name, source)
                builder_defs[name] = fn_text
              end
            end
          end
        end

        pending_router_args.each do |r_name, target_ident, r_line|
          if obj_info = object_decls[target_ident]?
            entries = extract_router_entries(obj_info[0], source, path, base_path, include_callees)
            line = obj_info[1] > 0 ? obj_info[1] : r_line
            routers << Router.new(base_path, r_name, entries, path, line)
          end
        end
      end

      TRPCFileFacts.new(routers, procedures, mount, url_prefix, builder_defs)
    end

    private def extract_router_entries(obj_node : LibTreeSitter::TSNode, source : String,
                                       path : String, base_path : String,
                                       include_callees : Bool) : Array(TRPCRouterEntry)
      entries = [] of TRPCRouterEntry

      Noir::TreeSitter.each_named_child(obj_node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "pair"
          key_node = Noir::TreeSitter.field(child, "key")
          key = property_key_name(key_node, source)
          val_node = Noir::TreeSitter.field(child, "value")
          next unless val_node
          val_u = Noir::TreeSitter.unwrap_expression(val_node)
          line = Noir::TreeSitter.node_start_row(child) + 1

          case Noir::TreeSitter.node_type(val_u)
          when "identifier"
            ident = Noir::TreeSitter.node_text(val_u, source)
            entries << TRPCRouterEntry.new(key, line, :identifier, ident, [] of TRPCRouterEntry, nil)
          when "call_expression"
            if router_call_node?(val_u, source)
              if args_node = Noir::TreeSitter.field(val_u, "arguments")
                if arg0 = Noir::TreeSitter.first_named_arg(args_node)
                  arg0_u = Noir::TreeSitter.unwrap_expression(arg0)
                  if Noir::TreeSitter.node_type(arg0_u) == "object"
                    sub_entries = extract_router_entries(arg0_u, source, path, base_path, include_callees)
                    entries << TRPCRouterEntry.new(key, line, :nested_router, "", sub_entries, nil)
                  end
                end
              end
            elsif procedure_chain?(val_u, source)
              proc_data = extract_procedure_data(val_u, source, path, include_callees)
              entries << TRPCRouterEntry.new(key, line, :procedure, "", [] of TRPCRouterEntry, proc_data)
            end
          when "object"
            sub_entries = extract_router_entries(val_u, source, path, base_path, include_callees)
            entries << TRPCRouterEntry.new(key, line, :nested_router, "", sub_entries, nil)
          end
        when "shorthand_property_identifier"
          name = Noir::TreeSitter.node_text(child, source)
          line = Noir::TreeSitter.node_start_row(child) + 1
          entries << TRPCRouterEntry.new(name, line, :identifier, name, [] of TRPCRouterEntry, nil)
        end
      end

      entries
    end

    private def router_call_node?(node : LibTreeSitter::TSNode, source : String) : Bool
      return false unless Noir::TreeSitter.node_type(node) == "call_expression"
      fn = Noir::TreeSitter.field(node, "function") || return false
      fn_u = Noir::TreeSitter.unwrap_expression(fn)
      fn_text = Noir::TreeSitter.node_text(fn_u, source)
      router_call?(fn_text)
    end

    private def router_call?(fn_name : String) : Bool
      fn_name == "router" ||
        fn_name.ends_with?(".router") ||
        fn_name == "createTRPCRouter" ||
        fn_name.ends_with?(".createTRPCRouter")
    end

    private def procedure_chain?(node : LibTreeSitter::TSNode, source : String) : Bool
      return false unless Noir::TreeSitter.node_type(node) == "call_expression"
      fn = Noir::TreeSitter.field(node, "function") || return false
      fn_u = Noir::TreeSitter.unwrap_expression(fn)
      return false unless Noir::TreeSitter.node_type(fn_u) == "member_expression"
      prop = Noir::TreeSitter.field(fn_u, "property") || return false
      prop_name = property_key_name(prop, source)
      {"query", "mutation", "subscription"}.includes?(prop_name)
    end

    private V9_CHAIN_METHODS = {"query", "mutation", "subscription", "merge", "middleware"}

    private def v9_chain_router?(node : LibTreeSitter::TSNode, source : String) : Bool
      curr = node
      has_chain_methods = false
      while Noir::TreeSitter.node_type(curr) == "call_expression"
        fn = Noir::TreeSitter.field(curr, "function")
        break unless fn
        fn_u = Noir::TreeSitter.unwrap_expression(fn)
        if Noir::TreeSitter.node_type(fn_u) == "member_expression"
          prop = Noir::TreeSitter.field(fn_u, "property")
          prop_name = property_key_name(prop, source)
          if V9_CHAIN_METHODS.includes?(prop_name)
            has_chain_methods = true
            if obj = Noir::TreeSitter.field(fn_u, "object")
              curr = Noir::TreeSitter.unwrap_expression(obj)
              next
            end
          end
        end
        break
      end
      return false unless has_chain_methods
      v9_router_root?(curr, source)
    end

    private def v9_router_root?(node : LibTreeSitter::TSNode, source : String) : Bool
      return false unless Noir::TreeSitter.node_type(node) == "call_expression"
      fn = Noir::TreeSitter.field(node, "function") || return false
      fn_u = Noir::TreeSitter.unwrap_expression(fn)
      case Noir::TreeSitter.node_type(fn_u)
      when "identifier"
        Noir::TreeSitter.node_text(fn_u, source) == "createRouter"
      when "member_expression"
        prop = Noir::TreeSitter.field(fn_u, "property") || return false
        prop_name = property_key_name(prop, source)
        prop_name == "createRouter" || prop_name == "router"
      else
        false
      end
    end

    private def extract_v9_chain_entries(node : LibTreeSitter::TSNode, source : String,
                                         path : String, base_path : String,
                                         include_callees : Bool) : Array(TRPCRouterEntry)
      entries = [] of TRPCRouterEntry
      curr = node
      while Noir::TreeSitter.node_type(curr) == "call_expression"
        fn = Noir::TreeSitter.field(curr, "function")
        break unless fn
        fn_u = Noir::TreeSitter.unwrap_expression(fn)
        break unless Noir::TreeSitter.node_type(fn_u) == "member_expression"
        prop = Noir::TreeSitter.field(fn_u, "property")
        prop_name = property_key_name(prop, source)
        line = prop ? Noir::TreeSitter.node_start_row(prop) + 1 : Noir::TreeSitter.node_start_row(curr) + 1

        args_node = Noir::TreeSitter.field(curr, "arguments")
        args = [] of LibTreeSitter::TSNode
        if args_node
          Noir::TreeSitter.each_named_arg(args_node) { |a| args << a }
        end

        case prop_name
        when "query", "mutation", "subscription"
          if args.size >= 1
            route_name = decode_string(Noir::TreeSitter.unwrap_expression(args[0]), source) || ""
            unless route_name.empty?
              method = PROCEDURE_VERBS[prop_name]? || "GET"
              params = [] of Param
              param_type = method == "POST" ? "body" : "query"
              handler_node = nil.as(LibTreeSitter::TSNode?)

              if args.size >= 2
                opt_node = Noir::TreeSitter.unwrap_expression(args[1])
                if Noir::TreeSitter.node_type(opt_node) == "object"
                  if input_val = extract_prop_value(opt_node, "input", source)
                    params = extract_zod_params_from_node(input_val, param_type, source)
                  end
                  if res_val = extract_prop_value(opt_node, "resolve", source)
                    handler_node = Noir::TreeSitter.unwrap_expression(res_val)
                  end
                end
              end

              callees = (include_callees && handler_node) ? Noir::JSCalleeExtractor.callees_for_handler_node(handler_node, source, path) : [] of Noir::JSCalleeExtractor::Entry
              body_text = ""
              if hn = handler_node
                body_node = Noir::TreeSitter.field(hn, "body") || hn
                body_text = Noir::TreeSitter.node_text(body_node, source)
              end
              handler = procedure_handler(body_text, path, line, "")

              proc_data = TRPCProcedureData.new(method, line, path, "", params, callees, handler, nil)
              entries << TRPCRouterEntry.new(route_name, line, :procedure, "", [] of TRPCRouterEntry, proc_data)
            end
          end
        when "merge"
          if args.size >= 1
            prefix : String? = nil
            child = if args.size >= 2
                      prefix = decode_string(Noir::TreeSitter.unwrap_expression(args[0]), source)
                      Noir::TreeSitter.node_text(Noir::TreeSitter.unwrap_expression(args[1]), source)
                    else
                      Noir::TreeSitter.node_text(Noir::TreeSitter.unwrap_expression(args[0]), source)
                    end

            unless child.empty?
              key = normalize_v9_merge_prefix(prefix, child)
              unless key.empty?
                entries << TRPCRouterEntry.new(key, line, :identifier, child, [] of TRPCRouterEntry, nil)
              end
            end
          end
        end

        if obj = Noir::TreeSitter.field(fn_u, "object")
          curr = Noir::TreeSitter.unwrap_expression(obj)
        else
          break
        end
      end

      entries.reverse!
    end

    private def extract_procedure_data(call_node : LibTreeSitter::TSNode, source : String,
                                       path : String, include_callees : Bool) : TRPCProcedureData
      fallback_line = Noir::TreeSitter.node_start_row(call_node) + 1
      fn = Noir::TreeSitter.field(call_node, "function") || return TRPCProcedureData.new(
        "GET",
        fallback_line,
        path,
        "",
        [] of Param,
        [] of Noir::JSCalleeExtractor::Entry,
        Handler.new("", path, fallback_line),
        nil
      )
      fn_u = Noir::TreeSitter.unwrap_expression(fn)
      prop = Noir::TreeSitter.field(fn_u, "property")
      verb = prop ? property_key_name(prop, source) : ""
      method = PROCEDURE_VERBS[verb]? || "GET"
      line = fallback_line

      handler_node = nil.as(LibTreeSitter::TSNode?)
      if args_node = Noir::TreeSitter.field(call_node, "arguments")
        if arg0 = Noir::TreeSitter.first_named_arg(args_node)
          arg0_u = Noir::TreeSitter.unwrap_expression(arg0)
          if {"arrow_function", "function_expression", "function_declaration"}.includes?(Noir::TreeSitter.node_type(arg0_u))
            handler_node = arg0_u
          end
        end
      end

      callees = (include_callees && handler_node) ? Noir::JSCalleeExtractor.callees_for_handler_node(handler_node, source, path) : [] of Noir::JSCalleeExtractor::Entry

      handler = Handler.new("", path, line)
      if hn = handler_node
        body_node = Noir::TreeSitter.field(hn, "body") || hn
        body_text = Noir::TreeSitter.node_text(body_node, source)
        handler = procedure_handler(body_text, path, line, "")
      end

      params = [] of Param
      param_type = method == "POST" ? "body" : "query"
      seen = Set(String).new
      had_input = false

      # The full receiver of the terminal call, so a call-form base such as
      # `createXProcedure("p").input(...)` keeps its callee name.
      outer_fn = Noir::TreeSitter.field(call_node, "function")
      outer_obj = outer_fn ? Noir::TreeSitter.field(Noir::TreeSitter.unwrap_expression(outer_fn), "object") : nil
      chain_text = outer_obj ? Noir::TreeSitter.node_text(outer_obj, source) : ""

      input_nodes = [] of LibTreeSitter::TSNode
      curr = call_node
      while Noir::TreeSitter.node_type(curr) == "call_expression"
        fn = Noir::TreeSitter.field(curr, "function")
        break unless fn
        fn_u = Noir::TreeSitter.unwrap_expression(fn)
        if Noir::TreeSitter.node_type(fn_u) == "member_expression"
          prop = Noir::TreeSitter.field(fn_u, "property")
          if property_key_name(prop, source) == "input"
            had_input = true
            if args_node = Noir::TreeSitter.field(curr, "arguments")
              if arg0 = Noir::TreeSitter.first_named_arg(args_node)
                input_nodes << Noir::TreeSitter.unwrap_expression(arg0)
              end
            end
          end
          if obj = Noir::TreeSitter.field(fn_u, "object")
            curr = Noir::TreeSitter.unwrap_expression(obj)
          else
            break
          end
        else
          break
        end
      end

      input_nodes.reverse_each do |inp|
        extract_zod_params_into(inp, param_type, source, params, seen)
      end

      if params.empty? && had_input
        params << Param.new("input", "", param_type)
      end

      TRPCProcedureData.new(method, line, path, chain_text, params, callees, handler, nil)
    end

    private def extract_zod_params_from_node(node : LibTreeSitter::TSNode, param_type : String, source : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new
      extract_zod_params_into(node, param_type, source, params, seen)
      if params.empty?
        params << Param.new("input", "", param_type)
      end
      params
    end

    private def extract_zod_params_into(node : LibTreeSitter::TSNode, param_type : String, source : String,
                                        params : Array(Param), seen : Set(String)) : Nil
      found_objs = [] of LibTreeSitter::TSNode
      collect_zod_schema_objects(node, found_objs, source)

      found_objs.each do |obj|
        Noir::TreeSitter.each_named_child(obj) do |child|
          case Noir::TreeSitter.node_type(child)
          when "pair"
            k = Noir::TreeSitter.field(child, "key")
            pname = property_key_name(k, source)
            if !pname.empty? && pname != "z" && seen.add?(pname)
              params << Param.new(pname, "", param_type)
            end
          when "shorthand_property_identifier"
            pname = Noir::TreeSitter.node_text(child, source)
            if !pname.empty? && pname != "z" && seen.add?(pname)
              params << Param.new(pname, "", param_type)
            end
          end
        end
      end
    end

    private def collect_zod_schema_objects(node : LibTreeSitter::TSNode, found_objs : Array(LibTreeSitter::TSNode), source : String) : Nil
      node_u = Noir::TreeSitter.unwrap_expression(node)
      case Noir::TreeSitter.node_type(node_u)
      when "object"
        found_objs << node_u
      when "array"
        Noir::TreeSitter.each_named_arg(node_u) do |elem|
          collect_zod_schema_objects(elem, found_objs, source)
        end
      when "call_expression"
        fn = Noir::TreeSitter.field(node_u, "function") || return
        fn_u = Noir::TreeSitter.unwrap_expression(fn)
        name = if Noir::TreeSitter.node_type(fn_u) == "member_expression"
                 prop = Noir::TreeSitter.field(fn_u, "property")
                 property_key_name(prop, source)
               else
                 property_key_name(fn_u, source)
               end
        fn_text = Noir::TreeSitter.node_text(fn_u, source)

        if name == "object" || fn_text.ends_with?(".object")
          if args_node = Noir::TreeSitter.field(node_u, "arguments")
            if arg0 = Noir::TreeSitter.first_named_arg(args_node)
              arg0_u = Noir::TreeSitter.unwrap_expression(arg0)
              if Noir::TreeSitter.node_type(arg0_u) == "object"
                found_objs << arg0_u
              end
            end
          end
        elsif {"merge", "extend", "and", "intersection"}.includes?(name) ||
              fn_text.ends_with?(".merge") || fn_text.ends_with?(".extend") || fn_text.ends_with?(".and") || fn_text.ends_with?(".intersection")
          if Noir::TreeSitter.node_type(fn_u) == "member_expression"
            if obj = Noir::TreeSitter.field(fn_u, "object")
              collect_zod_schema_objects(obj, found_objs, source)
            end
          end
          if args_node = Noir::TreeSitter.field(node_u, "arguments")
            Noir::TreeSitter.each_named_arg(args_node) do |arg|
              collect_zod_schema_objects(arg, found_objs, source)
            end
          end
        elsif {"union", "discriminatedUnion"}.includes?(name) ||
              fn_text.ends_with?(".union") || fn_text.ends_with?(".discriminatedUnion")
          if args_node = Noir::TreeSitter.field(node_u, "arguments")
            Noir::TreeSitter.each_named_arg(args_node) do |arg|
              collect_zod_schema_objects(arg, found_objs, source)
            end
          end
        else
          if Noir::TreeSitter.node_type(fn_u) == "member_expression"
            if obj = Noir::TreeSitter.field(fn_u, "object")
              collect_zod_schema_objects(obj, found_objs, source)
            end
          end
        end
      end
    end

    private def property_key_name(node : LibTreeSitter::TSNode?, source : String) : String
      return "" unless node
      unwrapped = Noir::TreeSitter.unwrap_expression(node)
      case Noir::TreeSitter.node_type(unwrapped)
      when "identifier", "property_identifier"
        Noir::TreeSitter.node_text(unwrapped, source)
      when "string", "template_string"
        decode_string(unwrapped, source) || ""
      when "computed_property_name"
        if inner = Noir::TreeSitter.first_named_child(unwrapped)
          property_key_name(inner, source)
        else
          ""
        end
      else
        ""
      end
    end
  end
end
