require "../../engines/python_engine"
require "./python_helper"

module Analyzer::Python
  class CherryPy < PythonEngine
    analyzer_for "python_cherrypy"

    # Reference: https://docs.cherrypy.dev/en/latest/basics.html
    #            https://docs.cherrypy.dev/en/latest/tutorials.html
    #
    # CherryPy's DEFAULT dispatcher is object-traversal, not explicit route
    # registration: URL path segments walk a tree of nested Python objects,
    # and any `@cherrypy.expose`d method becomes a URL segment named after
    # itself (with `index` serving the object's own path and `default`
    # acting as a catch-all for otherwise-unmatched trailing segments).
    #
    #   class Users:
    #       @cherrypy.expose
    #       def index(self):       # -> GET /users/
    #           ...
    #       @cherrypy.expose
    #       def profile(self, id): # -> GET /users/profile/<id>
    #           ...
    #
    #   class Root:
    #       users = Users()
    #       @cherrypy.expose
    #       def index(self):       # -> GET /
    #           ...
    #
    #   cherrypy.quickstart(Root())
    #
    # There is no route string anywhere in this source — the URL is
    # *inferred* by walking the object graph starting from whatever is
    # passed to `cherrypy.quickstart()` / `cherrypy.tree.mount()` /
    # `cherrypy.Application()`. This analyzer reconstructs that walk
    # statically:
    #
    #   1. Find every `cherrypy.quickstart(root_expr, prefix)` /
    #      `cherrypy.tree.mount(root_expr, prefix)` /
    #      `cherrypy.Application(root_expr, prefix)` call and resolve
    #      `root_expr` to the class that defines the root object (bare
    #      `Root()`, a pre-assigned variable, or a cross-file/cross-module
    #      reference — the same `import_map` cross-file resolution the
    #      Falcon analyzer uses for resource classes).
    #   2. Walk that class's `@cherrypy.expose`d methods, mapping each
    #      method name to a URL segment (see path-mapping rules below),
    #      and each simple `attr = SomeClass()` class-body assignment to
    #      a nested branch of the tree, recursing into `SomeClass`.
    #
    # CherryPy also supports an explicit REST-ish alternative,
    # `MethodDispatcher`, configured per mount point via
    # `{'request.dispatch': cherrypy.dispatch.MethodDispatcher()}`. Under
    # that dispatcher a whole class is exposed (`@cherrypy.expose` on the
    # class itself, or a bare `exposed = True` class attribute) and its
    # UPPERCASE HTTP-verb-named methods (`GET`, `POST`, `PUT`, `DELETE`, …)
    # answer that verb directly at the class's own URL — no extra path
    # segment for the method name. Rather than trace which mount points
    # are actually configured with `MethodDispatcher` (real config wiring
    # is often in a separate file/dict noir can't reliably bind back to a
    # mount call), this analyzer applies the MethodDispatcher shape
    # per-method: an exposed method whose name is a bare HTTP verb
    # (`GET`/`POST`/`PUT`/`DELETE`/`PATCH`/`HEAD`/`OPTIONS`/`QUERY`) is
    # always treated as a MethodDispatcher leaf, since that naming only
    # occurs in practice under that dispatcher.
    #
    # KNOWN LIMITATIONS (see PR description for the full writeup):
    #   * Traversal dispatch is method-agnostic in CherryPy — any exposed
    #     method answers any HTTP verb unless the handler itself checks
    #     `cherrypy.request.method`. We report "GET" for these, matching
    #     every other framework-analyzer's "no explicit method" default.
    #   * A required (no-default) parameter on a traversal method is
    #     reported as a synthesized `<name>` path segment appended after
    #     the method's own segment — CherryPy consumes leftover URL
    #     segments positionally, but the literal value is never in the
    #     source. `index`'s required params (rare, and can't be
    #     positionally sourced) fold into query/form instead.
    #   * `default(self, *args)` is reported as a `/*` glob; the
    #     variadic positional args it actually receives aren't enumerable
    #     from static source.
    #   * Only local, statically-resolvable nested router objects are
    #     followed (`attr = SomeClass()` / `attr = some_var` where
    #     `some_var` was itself assigned that way) — dynamic composition
    #     (building the tree from a loop/dict/plugin registry) isn't
    #     followed.

    HTTP_VERB_NAMES = Set{"GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "QUERY"}
    # QUERY (RFC 10008) carries a request body like POST/PUT, so it is
    # excluded from the body-less set even though it's a "read" verb.
    NON_BODY_VERBS = Set{"GET", "HEAD", "DELETE", "OPTIONS"}

    MAX_DEPTH = 8

    # Group 1 (optional `self.`) tells the class-body walk whether this is
    # a bare class-attribute assignment or a `self.`-attribute assignment,
    # which matters for scoping nested-router discovery (see `walk_class`).
    CALL_ASSIGN_RE  = /^\s*(self\.)?([A-Za-z_]\w*)\s*=\s*((?:[A-Za-z_]\w*\.)*[A-Za-z_]\w*)\s*\(/
    ALIAS_ASSIGN_RE = /^\s*(self\.)?([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*$/
    # Whole-file variant (no self.-scoping needed): used only to resolve
    # the object expression passed to quickstart()/tree.mount(), which is
    # always a plain module-level assignment, never a `self.` attribute.
    ROOT_VAR_CALL_ASSIGN_RE  = /^\s*([A-Za-z_]\w*)\s*=\s*((?:[A-Za-z_]\w*\.)*[A-Za-z_]\w*)\s*\(/
    ROOT_VAR_ALIAS_ASSIGN_RE = /^\s*([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*$/
    CLASS_DEF_RE             = /^\s*class\s+([A-Za-z_]\w*)\s*[\(:]/
    DEF_RE                   = /^(?:async\s+)?def\s+([A-Za-z_]\w*)\s*\(/
    EXPOSE_DECO_RE           = /^@(?:cherrypy\.)?expose\b/

    # Per-file/per-project caches, built once and shared across the whole
    # walk so cross-file class resolution (imported nested resource
    # classes, à la the Falcon analyzer) doesn't re-read/re-parse a file
    # for every reference to it.
    class ProjectIndex
      getter class_registry = Hash(::String, Hash(::String, Int32)).new
      getter instance_registry = Hash(::String, Hash(::String, ::String)).new
      getter import_maps = Hash(::String, Hash(::String, Tuple(::String, Int32))).new
      getter source_cache = Hash(::String, ::String).new
    end

    def analyze
      reg = ProjectIndex.new
      root_calls = [] of Tuple(::String, ::String, ::String, ::String) # {origin_file, definition_base_path, root_expr, prefix}

      files = python_source_files
      base_paths.each do |current_base_path|
        files.each do |path|
          next unless path_under_root?(path, current_base_path)

          begin
            content = read_file_content(path)
            next unless content.includes?("cherrypy")

            reg.source_cache[path] = content
            lines = sanitize_python_lines(content.lines)
            reg.class_registry[path] = collect_classes(lines)
            reg.instance_registry[path] = collect_instance_registry(lines)
            reg.import_maps[path] = find_imported_modules(current_base_path, path, content)

            find_root_calls(lines).each do |root_expr, prefix|
              root_calls << {path, current_base_path, root_expr, prefix}
            end
          rescue e
            @logger.debug "Error analyzing #{path}: #{e}"
          end
        end
      end

      root_calls.each do |origin_file, definition_base_path, root_expr, prefix|
        begin
          resolved = resolve_class_ref(root_expr, origin_file, reg)
          next unless resolved
          target_file, target_start_line = resolved

          # A common real-world (and official-tutorial) composition style
          # mounts children onto the root object *after* construction —
          # `root = HomePage(); root.joke = JokePage()` — rather than as
          # class-body attributes. That's a plain module-level statement,
          # outside any class body, so `walk_class`'s own class-body scan
          # never sees it; seed it in explicitly for the root object when
          # `root_expr` is a bare variable reference.
          extra_attr_targets = [] of Tuple(::String, ::String)
          bare_root_var = root_expr.strip
          if !bare_root_var.empty? && !bare_root_var.includes?('(') && !bare_root_var.includes?('.')
            origin_source = reg.source_cache[origin_file]? || read_file_content(origin_file)
            extra_attr_targets = collect_external_attr_assignments(sanitize_python_lines(origin_source.lines), bare_root_var)
          end

          visited = Set(::String).new
          walk_class(reg, target_file, target_start_line, Helper.normalize_path(prefix), 0, definition_base_path, visited, extra_attr_targets)
        rescue e
          @logger.debug "Error walking CherryPy root in #{origin_file}: #{e}"
        end
      end

      result
    end

    # Blank out (replace with "") every line that falls inside a
    # triple-quoted string. Library and application code alike commonly
    # embeds example snippets in a module/class docstring (CherryPy's own
    # `cherrypy/lib/profiler.py` has a `class Root: ... cherrypy.tree.
    # mount(Root())` usage example in its module docstring) — without this,
    # every regex-based structural scan below (`class` detection, root-call
    # detection, `@expose`d-method detection, nested-attribute detection)
    # would treat that documentation text as real code and synthesize
    # phantom endpoints from it.
    #
    # Deliberately simple: tracks only triple-quote (`'''`/`"""`) regions
    # spanning one or more lines, doesn't special-case a triple-quote
    # delimiter appearing inside a single-line non-triple string (rare),
    # and blanks the *whole* line a docstring closes on even if real code
    # follows the closing delimiter on that same line (rare style). Good
    # enough to eliminate the common multi-line-docstring false positive
    # without a full tokenizer.
    private def sanitize_python_lines(lines : Array(::String)) : Array(::String)
      in_triple : ::String? = nil
      lines.map do |line|
        if current = in_triple
          close_index = line.index(current)
          if close_index
            in_triple = nil
          end
          next ""
        end

        pos = 0
        while pos < line.size
          double_index = line.index("\"\"\"", pos)
          single_index = line.index("'''", pos)
          open_index = [double_index, single_index].compact.min?
          break unless open_index

          delimiter = line[open_index, 3]
          close_index = line.index(delimiter, open_index + 3)
          if close_index
            pos = close_index + 3
          else
            in_triple = delimiter
            break
          end
        end

        line
      end
    end

    # --- Root-object discovery -------------------------------------------

    private def find_root_calls(lines : Array(::String)) : Array(Tuple(::String, ::String))
      calls = [] of Tuple(::String, ::String)

      lines.each_with_index do |line, index|
        next unless line.includes?("cherrypy.quickstart(") ||
                    line.includes?("cherrypy.tree.mount(") ||
                    line.includes?("cherrypy.Application(")

        effective_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, index, line) : line
        call_match = effective_line.match(/cherrypy\.(?:quickstart|tree\.mount|Application)\s*\((.*)\)\s*$/m)
        next unless call_match

        args = split_python_arguments(call_match[1])
        next if args.empty?

        root_expr = args[0].strip
        next if root_expr.empty?

        prefix = ""
        if second = args[1]?
          second = second.strip
          if kw = second.match(/^script_name\s*=\s*(.+)$/m)
            prefix = Helper.extract_python_string(kw[1]) || ""
          elsif str = Helper.extract_python_string(second)
            prefix = str
          end
        end
        args.each do |arg|
          if kw = arg.match(/^\s*script_name\s*=\s*(.+)$/m)
            prefix = Helper.extract_python_string(kw[1]) || prefix
          end
        end

        calls << {root_expr, prefix}
      end

      calls
    end

    # --- Cross-file class resolution --------------------------------------

    private def resolve_class_ref(ref : ::String, origin_file : ::String, reg : ProjectIndex) : Tuple(::String, Int32)?
      callable = ref.includes?('(') ? ref[0...ref.index!('(')] : ref
      callable = callable.strip
      return if callable.empty?

      current = callable
      hops = 0
      while hops < 5 && !current.includes?('.')
        aliased = reg.instance_registry[origin_file]?.try(&.[current]?)
        break unless aliased
        break if aliased == current
        current = aliased
        hops += 1
      end

      parts = current.split('.')
      return if parts.empty? || parts[0].empty?

      if parts.size == 1
        class_name = parts[0]
        if start_line = reg.class_registry[origin_file]?.try(&.[class_name]?)
          return {origin_file, start_line}
        end
        if imported = reg.import_maps[origin_file]?.try(&.[class_name]?)
          return resolve_class_in_file(imported[0], class_name, reg)
        end
        return
      end

      import_name = parts[0]
      class_name = parts[-1]
      return unless imported = reg.import_maps[origin_file]?.try(&.[import_name]?)
      resolve_class_in_file(imported[0], class_name, reg)
    end

    private def resolve_class_in_file(file_path : ::String, class_name : ::String, reg : ProjectIndex) : Tuple(::String, Int32)?
      return if file_path.empty? || !File.exists?(file_path)

      source = reg.source_cache[file_path] ||= read_file_content(file_path)
      classes = reg.class_registry[file_path] ||= collect_classes(sanitize_python_lines(source.lines))
      return unless start_line = classes[class_name]?

      {file_path, start_line}
    end

    private def collect_classes(lines : Array(::String)) : Hash(::String, Int32)
      classes = Hash(::String, Int32).new
      lines.each_with_index do |line, index|
        if m = line.match(CLASS_DEF_RE)
          classes[m[1]] = index
        end
      end
      classes
    end

    # `var = SomeClass(...)` (direct instantiation, class-body or
    # `self.` attribute form) and `var = other_var` (aliasing an
    # already-instantiated object) — used both to resolve the object
    # passed to `quickstart`/`tree.mount` and to resolve `attr = existing`
    # nested-router assignments inside a class body.
    private def collect_instance_registry(lines : Array(::String)) : Hash(::String, ::String)
      registry = Hash(::String, ::String).new
      lines.each do |line|
        next if line.lstrip.starts_with?('#')

        if m = line.match(ROOT_VAR_CALL_ASSIGN_RE)
          registry[m[1]] = m[2]
        elsif m = line.match(ROOT_VAR_ALIAS_ASSIGN_RE)
          registry[m[1]] ||= m[2]
        end
      end
      registry
    end

    # `<receiver>.<attr> = SomeClass(...)` at module level — the
    # post-hoc composition style used by CherryPy's own tutorials
    # (`root = HomePage(); root.joke = JokePage()`), as opposed to a
    # class-body attribute or a `self.` assignment inside `__init__`.
    private def collect_external_attr_assignments(lines : Array(::String), receiver : ::String) : Array(Tuple(::String, ::String))
      targets = [] of Tuple(::String, ::String)
      re = /^\s*#{Regex.escape(receiver)}\.([A-Za-z_]\w*)\s*=\s*((?:[A-Za-z_]\w*\.)*[A-Za-z_]\w*)\s*\(/
      lines.each do |line|
        next if line.lstrip.starts_with?('#')
        if m = line.match(re)
          targets << {m[1], m[2]}
        end
      end
      targets
    end

    # --- The traversal walk ------------------------------------------------

    private def walk_class(reg : ProjectIndex,
                           file_path : ::String,
                           class_start_line : Int32,
                           url_path : ::String,
                           depth : Int32,
                           definition_base_path : ::String,
                           visited : Set(::String),
                           extra_attr_targets : Array(Tuple(::String, ::String)) = [] of Tuple(::String, ::String))
      return if depth > MAX_DEPTH

      key = "#{file_path}::#{class_start_line}::#{url_path}"
      return if visited.includes?(key)
      visited << key

      source = reg.source_cache[file_path] ||= read_file_content(file_path)
      lines = sanitize_python_lines(source.lines)
      return if class_start_line >= lines.size

      class_indent = indent_level(lines[class_start_line])
      class_level_expose_all = class_decorated_expose?(lines, class_start_line)

      exposed_defs = Hash(Int32, ::String).new
      attr_targets = [] of Tuple(::String, ::String)
      header_region = true

      # Nested-router discovery (`attr = SomeClass()`) is scoped to avoid
      # mistaking an ordinary local variable inside a request handler for
      # a router attribute: a bare `attr = SomeClass()` is only accepted
      # directly in the class body (not inside any `def`), and a
      # `self.attr = SomeClass()` form is only accepted inside `__init__`
      # — the two idiomatic places CherryPy apps build the object tree.
      current_def_name : ::String? = nil
      current_def_indent : Int32? = nil

      i = class_start_line + 1
      while i < lines.size
        line = lines[i]
        stripped = line.lstrip

        unless stripped.empty? || stripped.starts_with?('#')
          break if indent_level(line) <= class_indent

          if def_indent = current_def_indent
            if indent_level(line) <= def_indent
              current_def_name = nil
              current_def_indent = nil
            end
          end

          if def_match = stripped.match(DEF_RE)
            header_region = false
            method_name = def_match[1]
            if class_level_expose_all && HTTP_VERB_NAMES.includes?(method_name)
              exposed_defs[i] = method_name
            end
            current_def_name = method_name
            current_def_indent = indent_level(line)
          elsif stripped.match(EXPOSE_DECO_RE)
            if (def_line = find_def_line(lines, i)) && (dm = lines[def_line].lstrip.match(DEF_RE))
              exposed_defs[def_line] = dm[1]
            end
          elsif header_region && stripped.match(/^exposed\s*=\s*True\b/)
            class_level_expose_all = true
          end

          in_init = current_def_name == "__init__"
          at_class_level = current_def_name.nil?
          if at_class_level || in_init
            if attr_match = line.match(CALL_ASSIGN_RE)
              self_prefixed = !attr_match[1]?.nil?
              if (at_class_level && !self_prefixed) || (in_init && self_prefixed)
                attr_targets << {attr_match[2], attr_match[3]}
              end
            elsif attr_match = line.match(ALIAS_ASSIGN_RE)
              self_prefixed = !attr_match[1]?.nil?
              if (at_class_level && !self_prefixed) || (in_init && self_prefixed)
                attr_targets << {attr_match[2], attr_match[3]}
              end
            end
          end
        end

        i += 1
      end

      exposed_defs.each do |exposed_def_line, exposed_method_name|
        emit_endpoint(reg, file_path, source, lines, exposed_def_line, exposed_method_name, url_path, definition_base_path)
      end

      attr_targets.concat(extra_attr_targets)

      attr_targets.each do |attr_name, class_ref|
        next if attr_name == "self"
        resolved = resolve_class_ref(class_ref, file_path, reg)
        next unless resolved
        target_file, target_start_line = resolved

        target_source = reg.source_cache[target_file]? || read_file_content(target_file)
        reg.source_cache[target_file] ||= target_source
        next unless target_source.includes?("expose")

        child_path = Helper.normalized_join(url_path, attr_name)
        walk_class(reg, target_file, target_start_line, child_path, depth + 1, definition_base_path, visited)
      end
    end

    private def class_decorated_expose?(lines : Array(::String), class_start_line : Int32) : Bool
      idx = class_start_line - 1
      checked = 0
      while idx >= 0 && checked < 8
        stripped = lines[idx].lstrip
        if stripped.empty?
          idx -= 1
          checked += 1
          next
        end
        return true if stripped.match(EXPOSE_DECO_RE)
        break unless stripped.starts_with?('@')
        idx -= 1
        checked += 1
      end
      false
    end

    # --- Endpoint emission ---------------------------------------------------

    private def emit_endpoint(reg : ProjectIndex,
                              file_path : ::String,
                              source : ::String,
                              lines : Array(::String),
                              def_line : Int32,
                              method_name : ::String,
                              url_path : ::String,
                              definition_base_path : ::String)
      function_definition = parse_function_def(lines, def_line)
      return unless function_definition

      # `p.name.strip.empty?` guards against a `parse_function_def` edge
      # case (shared across every Python analyzer): a multi-line
      # signature whose closing `):` line has leading indentation before
      # `)` — common with a trailing comma before the paren, e.g.
      #   def menu(
      #       self,
      #       base='/',
      #   ):
      # — yields a spurious empty-named trailing parameter.
      call_params = function_definition.params.reject do |p|
        p.name.in?({"self", "cls"}) || p.name.starts_with?('*') || p.name.strip.empty?
      end
      required_names = call_params.select(&.default.strip.empty?).map(&.name)
      optional_names = call_params.reject(&.default.strip.empty?).map(&.name)
      uses_kwargs = function_definition.params.any?(&.name.starts_with?("**"))

      http_method : ::String
      endpoint_path : ::String
      path_param_names : Array(::String)
      folded_query_names : Array(::String)

      if HTTP_VERB_NAMES.includes?(method_name)
        http_method = method_name
        endpoint_path = append_path_params(Helper.normalize_path(url_path), required_names)
        path_param_names = required_names
        folded_query_names = [] of ::String
      elsif method_name == "index"
        http_method = "GET"
        base = Helper.normalize_path(url_path)
        endpoint_path = base == "/" ? "/" : "#{base}/"
        path_param_names = [] of ::String
        folded_query_names = required_names
      elsif method_name == "default"
        http_method = "GET"
        base = Helper.normalize_path(url_path)
        endpoint_path = base == "/" ? "/*" : "#{base}/*"
        path_param_names = [] of ::String
        folded_query_names = [] of ::String
      else
        http_method = "GET"
        endpoint_path = append_path_params(Helper.normalized_join(url_path, method_name), required_names)
        path_param_names = required_names
        folded_query_names = [] of ::String
      end

      body_like = HTTP_VERB_NAMES.includes?(method_name) && !NON_BODY_VERBS.includes?(method_name)
      kwarg_type = body_like ? "form" : "query"

      details = Details.new(PathInfo.new(file_path, def_line + 1))
      endpoint = Endpoint.new(endpoint_path, http_method, details)

      path_param_names.each { |name| endpoint.push_param(Param.new(name, "", "path")) }
      optional_names.each { |name| endpoint.push_param(Param.new(name, "", kwarg_type)) }
      folded_query_names.each { |name| endpoint.push_param(Param.new(name, "", kwarg_type)) }

      body = extract_function_body(lines, def_line)
      extract_request_params(body, uses_kwargs, kwarg_type).each { |p| endpoint.push_param(p) }

      push_callees_from(
        endpoint,
        body,
        def_line + 1,
        file_path,
        definition_base_path: definition_base_path,
        source: source
      )

      result << endpoint
    end

    private def append_path_params(url : ::String, names : Array(::String)) : ::String
      names.reduce(url) { |acc, name| Helper.normalized_join(acc, "<#{name}>") }
    end

    # `cherrypy.request.*` accessors read inside an exposed handler body.
    # `cherrypy.request.params` is CherryPy's already-merged query+form
    # dict, so it's reported as "query" (matching every other analyzer's
    # convention for an ambiguous combined accessor).
    private def extract_request_params(body : ::String, uses_kwargs : Bool, kwarg_type : ::String) : Array(Param)
      params = [] of Param
      seen = Set(::String).new
      record = ->(name : ::String, type : ::String) do
        key = "#{type}:#{name}"
        unless seen.includes?(key)
          params << Param.new(name, "", type)
          seen << key
        end
      end

      body.scan(/cherrypy\.request\.headers\s*\[\s*['"]([^'"]+)['"]\s*\]/) { |m| record.call(m[1], "header") }
      body.scan(/cherrypy\.request\.headers\.get\s*\(\s*['"]([^'"]+)['"]/) { |m| record.call(m[1], "header") }
      body.scan(/cherrypy\.request\.cookie\s*\[\s*['"]([^'"]+)['"]\s*\]/) { |m| record.call(m[1], "cookie") }
      body.scan(/cherrypy\.request\.json\s*\[\s*['"]([^'"]+)['"]\s*\]/) { |m| record.call(m[1], "json") }
      body.scan(/cherrypy\.request\.json\.get\s*\(\s*['"]([^'"]+)['"]/) { |m| record.call(m[1], "json") }
      body.scan(/cherrypy\.request\.params\s*\[\s*['"]([^'"]+)['"]\s*\]/) { |m| record.call(m[1], "query") }
      body.scan(/cherrypy\.request\.params\.get\s*\(\s*['"]([^'"]+)['"]/) { |m| record.call(m[1], "query") }

      if uses_kwargs
        body.scan(/(?:^|[^a-zA-Z0-9_])kwargs\s*\[\s*['"]([^'"]+)['"]\s*\]/) { |m| record.call(m[1], kwarg_type) }
        body.scan(/(?:^|[^a-zA-Z0-9_])kwargs\.get\s*\(\s*['"]([^'"]+)['"]/) { |m| record.call(m[1], kwarg_type) }
      end

      params
    end

    private def indent_level(line : ::String) : Int32
      line.size - line.lstrip.size
    end

    # Collect indented lines following a `def` as the function body.
    private def extract_function_body(lines : Array(::String), def_index : Int32) : ::String
      return "" if def_index >= lines.size
      def_line = lines[def_index]
      base_indent = def_line.size - def_line.lstrip.size

      body = [] of ::String
      i = def_index + 1
      while i < lines.size
        line = lines[i]
        if line.strip.empty?
          body << line
          i += 1
          next
        end
        current_indent = line.size - line.lstrip.size
        break if current_indent <= base_indent
        body << line
        i += 1
      end
      body.join("\n")
    end

    private def split_python_arguments(args : ::String) : Array(::String)
      parts = [] of ::String
      current = String::Builder.new
      paren_depth = 0
      bracket_depth = 0
      brace_depth = 0
      in_quote : Char? = nil
      escaped = false

      args.each_char do |ch|
        if in_quote
          current << ch
          if escaped
            escaped = false
          elsif ch == '\\'
            escaped = true
          elsif ch == in_quote
            in_quote = nil
          end
          next
        end

        case ch
        when '\'', '"'
          in_quote = ch
          current << ch
        when '('
          paren_depth += 1
          current << ch
        when ')'
          paren_depth -= 1 if paren_depth > 0
          current << ch
        when '['
          bracket_depth += 1
          current << ch
        when ']'
          bracket_depth -= 1 if bracket_depth > 0
          current << ch
        when '{'
          brace_depth += 1
          current << ch
        when '}'
          brace_depth -= 1 if brace_depth > 0
          current << ch
        when ','
          if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0
            parts << current.to_s
            current = String::Builder.new
          else
            current << ch
          end
        else
          current << ch
        end
      end

      parts << current.to_s
      parts
    end
  end
end
