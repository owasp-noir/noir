require "../../../models/analyzer"
require "../../../miniparsers/zig_callee_extractor"

module Analyzer::Zig
  # zap exposes routes two ways:
  #
  #   * Endpoint structs — a struct (often the whole file via
  #     `pub const X = @This();`) carrying a `path` slug and one verb method
  #     per supported HTTP method (`pub fn get/post/put/delete/patch/options/
  #     head`). The slug is usually bound where the endpoint is instantiated
  #     (`X.init("/users", …)`, `.{ .path = "/stop" }`), not inside the
  #     struct, so paths are resolved project-wide and keyed by struct type.
  #   * `zap.Router` — `router.handle_func("/p", &inst, &T.method)` and
  #     `router.handle_func_unbound("/p", handler)` map a path to a handler
  #     for any method.
  class Zap < Analyzer
    VERBS       = %w[get post put delete patch options head]
    VERB_METHOD = {
      "get" => "GET", "post" => "POST", "put" => "PUT", "delete" => "DELETE",
      "patch" => "PATCH", "options" => "OPTIONS", "head" => "HEAD",
    }

    STRUCT_DECL_RE = /(?:^|[^A-Za-z0-9_.])(?:pub\s+)?const\s+([A-Za-z_]\w*)\s*=\s*struct\s*\{/
    THIS_DECL_RE   = /(?:^|[^A-Za-z0-9_.])(?:pub\s+)?const\s+([A-Za-z_]\w*)\s*=\s*@This\(\)/
    FIELD_PATH_RE  = /\bpath\s*:\s*\[\]const u8\s*=\s*"([^"]*)"/
    # `.` is intentionally NOT in the lookbehind: endpoint types are commonly
    # reached through a namespace re-export (`Endpoints.UserWeb.init("/u")`),
    # and the meaningful key is the final segment (`UserWeb`), which is itself
    # preceded by a `.`.
    INIT_RE         = /(?<![A-Za-z0-9_])([A-Za-z_]\w*)\.init\s*\(([^()]*)\)/
    LITERAL_PATH_RE = /\.path\s*=\s*"([^"]*)"/
    HANDLE_FUNC_RE  = /\.\s*handle_func(_unbound)?\s*\(/
    IMPORT_RE       = /(?:pub\s+)?(?:const|var)\s+([A-Za-z_]\w*)\s*=\s*@import\(\s*"([^"]+\.zig)"\s*\)/

    private record StructRegion, name : String, start : Int32, stop : Int32

    # by_type:        instantiation type name => candidate URL paths.
    # aliases_by_file: absolute struct file => the identifiers other files
    #   import it as. Endpoint structs are idiomatically written as
    #   `const Self = @This();`, so a path bound at the instantiation site
    #   (`Foo.init("/x")`, `.{ .path = "/x" }`) is keyed by the *import alias*
    #   `Foo`, never the internal `Self`. Mapping file => aliases lets the
    #   struct recover its own bindings.
    private record PathBindings,
      by_type : Hash(String, Array(String)),
      aliases_by_file : Hash(String, Array(String))

    def analyze
      include_callee = callees_needed?
      zig_files = all_files.select(&.ends_with?(".zig"))

      bindings = build_path_bindings(zig_files)

      zig_files.each do |path|
        content = read_file_content(path)
        next unless content.includes?("zap")
        process_file(path, content, bindings, include_callee)
      end

      @result
    end

    # Collected across the whole project: type => candidate paths from
    # `init()` call sites and `.path = "…"` struct literals, plus the
    # file => import-alias map. Over-collection of `by_type` is harmless: a
    # binding is only consumed for a type later confirmed to be an endpoint
    # struct (one that defines verb methods).
    private def build_path_bindings(files : Array(String)) : PathBindings
      by_type = Hash(String, Array(String)).new
      aliases_by_file = Hash(String, Array(String)).new
      files.each do |path|
        content = read_file_content(path)
        text = Noir::ZigCalleeExtractor.strip_comments(content)

        if content.includes?("@import")
          dir = File.dirname(path)
          text.scan(IMPORT_RE) do |m|
            resolved = File.expand_path(File.join(dir, m[2]))
            list = aliases_by_file[resolved] ||= [] of String
            list << m[1] unless list.includes?(m[1])
          end
        end

        next unless content.includes?(".path") || content.includes?(".init(")

        text.scan(INIT_RE) do |m|
          type = m[1]
          if pm = m[2].match(/"(\/[^"]*)"/)
            add_binding(by_type, type, pm[1])
          end
        end

        text.scan(LITERAL_PATH_RE) do |m|
          lit = m[1]
          next if lit.empty? || lit == "(undefined)"
          if type = nearest_type_before(text, m.begin(0) || 0)
            add_binding(by_type, type, lit)
          end
        end
      end
      PathBindings.new(by_type, aliases_by_file)
    end

    private def add_binding(bindings, type, path)
      list = bindings[type] ||= [] of String
      list << path unless list.includes?(path)
    end

    # The last Uppercase-initial identifier in the window preceding a
    # `.path = "…"` literal — almost always the struct type being
    # instantiated. Liberal by design (see build_path_bindings). `.` is
    # allowed in the lookbehind so a namespaced type (`Endpoints.UserWeb`)
    # resolves to its final segment (`UserWeb`).
    private def nearest_type_before(text : String, offset : Int32) : String?
      start = offset > 160 ? offset - 160 : 0
      window = text[start...offset]
      type = nil
      window.scan(/(?<![A-Za-z0-9_])([A-Z][A-Za-z0-9_]*)/) { |m| type = m[1] }
      type
    end

    private def process_file(path : String, content : String, bindings : PathBindings, include_callee : Bool)
      comment_stripped = Noir::ZigCalleeExtractor.strip_comments(content)
      # Comments + all literals blanked once; reused for struct-region brace
      # matching and the `@This()` file-struct scan.
      stripped = Noir::ZigCalleeExtractor.strip_non_code(content)
      all_fns = Noir::ZigCalleeExtractor.function_table(content, path)

      explicit = explicit_struct_regions(stripped)
      emit_endpoint_structs(path, content, stripped, comment_stripped, bindings, explicit, all_fns, include_callee)
      emit_router_routes(path, content, comment_stripped, all_fns, include_callee)
    end

    private def explicit_struct_regions(stripped : String) : Array(StructRegion)
      chars = stripped.chars
      regions = [] of StructRegion
      stripped.scan(STRUCT_DECL_RE) do |m|
        name = m[1]
        brace = (m.end(0) || 0) - 1
        close = Noir::ZigCalleeExtractor.find_matching(chars, brace, '{', '}')
        next if close.nil?
        regions << StructRegion.new(name, brace, close)
      end
      regions
    end

    private def emit_endpoint_structs(path, content, stripped, comment_stripped, bindings, explicit, all_fns, include_callee)
      # Explicit `const X = struct { … }` endpoints.
      explicit.each do |region|
        verbs = verb_methods_in(all_fns, region.start, region.stop) do |off|
          innermost_region(explicit, off) == region
        end
        next if verbs.empty?
        paths = resolve_paths(region.name, path, comment_stripped, region.start, region.stop, bindings)
        emit_struct_endpoints(path, region.name, paths, verbs, include_callee)
      end

      # File-as-struct (`pub const X = @This();`) endpoints: every verb method
      # not already claimed by an explicit nested struct belongs to it.
      if m = stripped.match(THIS_DECL_RE)
        name = m[1]
        verbs = all_fns.select do |f|
          VERBS.includes?(f[:name]) && innermost_region(explicit, f[:open]).nil?
        end
        unless verbs.empty?
          paths = resolve_paths(name, path, comment_stripped, 0, content.size, bindings)
          emit_struct_endpoints(path, name, paths, verbs, include_callee)
        end
      end
    end

    private def verb_methods_in(all_fns, start, stop, &)
      all_fns.select do |f|
        next false unless VERBS.includes?(f[:name])
        next false unless f[:open] > start && f[:open] < stop
        yield f[:open]
      end
    end

    # The smallest explicit struct region containing `offset`, or nil.
    private def innermost_region(explicit : Array(StructRegion), offset : Int32) : StructRegion?
      best : StructRegion? = nil
      explicit.each do |r|
        next unless offset > r.start && offset < r.stop
        if best.nil? || (r.stop - r.start) < (best.stop - best.start)
          best = r
        end
      end
      best
    end

    # Resolve an endpoint struct's URL paths. Instantiation-site bindings
    # (keyed by the struct's own name and by every alias the file is imported
    # as) take precedence; a `path` field default is only the fallback for a
    # struct that is constructed bare (`.{}`). Preferring the binding drops a
    # dead/overridden field default (e.g. a copy-pasted `path = "/post"` that
    # the call site replaces with `.path = "/comment"`).
    private def resolve_paths(type : String, file_path : String, comment_stripped : String, start : Int32, stop : Int32, bindings : PathBindings) : Array(String)
      keys = [type]
      if aliases = bindings.aliases_by_file[File.expand_path(file_path)]?
        aliases.each { |a| keys << a unless keys.includes?(a) }
      end

      binding_paths = [] of String
      keys.each do |key|
        bindings.by_type[key]?.try(&.each { |p| binding_paths << p unless binding_paths.includes?(p) })
      end
      return binding_paths unless binding_paths.empty?

      field_paths = [] of String
      region = comment_stripped[start...stop]? || ""
      region.scan(FIELD_PATH_RE) do |m|
        lit = m[1]
        next if lit.empty? || lit == "(undefined)"
        field_paths << lit unless field_paths.includes?(lit)
      end
      field_paths
    end

    private def emit_struct_endpoints(path, type, paths, verbs, include_callee)
      return if paths.empty?
      paths.each do |url|
        verbs.each do |fn|
          method = VERB_METHOD[fn[:name]]
          details = Details.new(PathInfo.new(path, fn[:start_line]))
          endpoint = Endpoint.new(url, method, [] of Param, details)
          if include_callee
            callees = Noir::ZigCalleeExtractor.callees_for_body(fn[:body], path, fn[:start_line])
            Noir::ZigCalleeExtractor.attach_to(endpoint, callees) unless callees.empty?
          end
          @result << endpoint
        end
      end
    end

    # `router.handle_func("/p", …)` / `handle_func_unbound("/p", handler)`.
    private def emit_router_routes(path, content, comment_stripped, all_fns, include_callee)
      chars = comment_stripped.chars
      comment_stripped.scan(HANDLE_FUNC_RE) do |m|
        open_paren = (m.end(0) || 0) - 1
        close = Noir::ZigCalleeExtractor.find_matching(chars, open_paren, '(', ')')
        next if close.nil?
        args = comment_stripped[(open_paren + 1)...close]
        url_match = args.match(/\s*"([^"]*)"/)
        next if url_match.nil?
        url = url_match[1]
        next if url.empty?

        line = Noir::ZigCalleeExtractor.line_at(chars, m.begin(0) || 0)
        details = Details.new(PathInfo.new(path, line))
        endpoint = Endpoint.new(url, "GET", [] of Param, details)

        if include_callee
          if handler = router_handler_name(args)
            if body = all_fns.find { |f| f[:name] == handler }
              callees = Noir::ZigCalleeExtractor.callees_for_body(body[:body], path, body[:start_line])
              Noir::ZigCalleeExtractor.attach_to(endpoint, callees) unless callees.empty?
            end
          end
        end

        @result << endpoint
      end
    end

    # The handler argument's simple function name: the last `.`-segment of the
    # final `&Type.method` / bare identifier token in the call's argument list.
    private def router_handler_name(args : String) : String?
      candidates = [] of String
      args.scan(/&?\s*([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)/) do |m|
        token = m[1].gsub(/\s+/, "")
        candidates << token unless token.empty?
      end
      return if candidates.empty?
      last = candidates.last
      last.includes?('.') ? last.split('.').last : last
    end
  end
end
