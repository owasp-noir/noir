require "../../../miniparsers/python"
require "../../engines/python_engine"

module Analyzer::Python
  # State and helpers shared by the Flask and Quart analyzers: Quart
  # re-implements Flask's API 1:1 (request object, Blueprints,
  # `add_url_rule`, class-based views), so both read sources the same way.
  module FlaskFamily
    # Reference: https://stackoverflow.com/a/16664376
    # Reference: https://tedboy.github.io/flask/generated/generated/flask.Request.html
    REQUEST_PARAM_FIELDS = {
      "data"    => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "args"    => {["GET"], "query"},
      "form"    => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "files"   => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "values"  => {["GET", "POST", "PUT", "PATCH", "DELETE"], "query"},
      "json"    => {["POST", "PUT", "PATCH", "DELETE"], "json"},
      "cookies" => {nil, "cookie"},
      "headers" => {nil, "header"},
    }

    # `extract_request_params` runs once per route and used to rebuild
    # two PCRE2 patterns per request field on every call (8 fields × 2 =
    # 16 regex compilations per endpoint). PCRE2 JIT-compilation of an
    # interpolated regex literal is ~3µs and dominated Flask scan time
    # (profiling: ~50% of the analyzer). The field names are a fixed set,
    # so precompile the access patterns once here and reuse them.
    # Tuple shape: {noir_param_type, bracket_access_regex, get_access_regex}
    # The get-access pattern accepts `.get(` and `.getlist(`: Werkzeug's
    # request MultiDicts (`request.args`, `request.form`, …) expose
    # `getlist("key")` as the standard accessor for repeated keys
    # (`?tag=a&tag=b`), and it reads the same first string argument as the
    # key — so `.get(?:list)?` captures both without a separate pattern.
    REQUEST_PARAM_FIELD_PATTERNS = REQUEST_PARAM_FIELDS.map do |field_name, tuple|
      {
        tuple[1],
        Regex.new("request\\.#{field_name}\\[[rf]?['\"]([^'\"]*)['\"]\\]"),
        Regex.new("request\\.#{field_name}\\.get(?:list)?\\([rf]?['\"]([^'\"]*)['\"]"),
      }
    end

    @file_content_cache = Hash(::String, ::String).new
    @parsers = Hash(::String, PythonParser).new

    # JSON-variable access patterns interpolate a discovered (dynamic but
    # low-cardinality) identifier, so they can't be hoisted to constants —
    # memoize them per variable name instead.
    @json_param_regex_cache = Hash(::String, Tuple(Regex, Regex)).new

    private def json_param_regexes(json_variable_name : ::String) : Tuple(Regex, Regex)
      @json_param_regex_cache[json_variable_name] ||= {
        /[^a-zA-Z_]#{Regex.escape(json_variable_name)}\[[rf]?['"]([^'"]*)['"]\]/,
        /[^a-zA-Z_]#{Regex.escape(json_variable_name)}\.get\([rf]?['"]([^'"]*)['"]/,
      }
    end

    # Fetch file content, preferring the detector-populated global
    # cache. The per-analyzer `@file_content_cache` is kept on top to
    # keep the internal lookups (called 2–3× per file across the
    # class/blueprint passes) cheap even when the global cache is
    # disabled — otherwise the fallback would do that many fresh
    # `File.read` calls per file.
    private def fetch_file_content(path : ::String) : ::String
      @file_content_cache[path] ||= read_file_content(path)
    end

    # Get a parser for a given path
    def get_parser(path : ::String, content : ::String = "") : PythonParser
      @parsers[path] ||= create_parser(path, content)
      @parsers[path]
    end

    # Create a Python parser for a given path and content. The
    # parser walks the file with tree-sitter and recursively
    # absorbs globals from imported modules — no lexer step.
    def create_parser(path : ::String, content : ::String = "") : PythonParser
      content = fetch_file_content(path) if content.empty?
      PythonParser.new(path, content, @parsers, depth: 0)
    end

    # Build endpoints from a single route decoration: split on declared
    # `methods=[...]`, default to `method`, run the analyzer's own
    # `extract_request_params` over the handler body once and filter the
    # params per method.
    def get_endpoints(method : ::String, route_path : ::String, extra_params : ::String, codeblock_lines : Array(::String), prefix : ::String)
      endpoints = [] of Endpoint
      methods = [] of ::String

      if !prefix.ends_with?("/") && !route_path.starts_with?("/")
        prefix = "#{prefix}/"
      end

      methods_match = extra_params.match /methods\s*=\s*(.*)/
      if !methods_match.nil? && methods_match.size == 2
        methods_match[1].scan(/['"]([^'"]*)['"']/) do |m|
          method_name = m[1].upcase
          methods << method_name if PythonEngine::HTTP_METHODS.any? { |hm| hm.upcase == method_name }
        end
      end
      methods << method.upcase if methods.empty?

      suspicious_params = extract_request_params(codeblock_lines)

      methods.uniq.each do |http_method_name|
        route_url = "#{prefix}#{route_path}"
        route_url = "/#{route_url}" unless route_url.starts_with?("/")

        params = get_filtered_params(http_method_name, suspicious_params)
        endpoints << Endpoint.new(route_url.gsub("//", "/"), http_method_name, params)
      end

      endpoints
    end

    private def split_python_call_args(args_str : ::String) : Array(::String)
      parts = [] of ::String
      current = String::Builder.new
      paren_depth = 0
      bracket_depth = 0
      single_quote = false
      double_quote = false
      escaped = false

      args_str.each_char do |ch|
        if escaped
          current << ch
          escaped = false
          next
        end

        if ch == '\\'
          current << ch
          escaped = true
          next
        end

        if single_quote
          single_quote = false if ch == '\''
          current << ch
          next
        end

        if double_quote
          double_quote = false if ch == '"'
          current << ch
          next
        end

        case ch
        when '\''
          single_quote = true
        when '"'
          double_quote = true
        when '('
          paren_depth += 1
        when ')'
          paren_depth -= 1 if paren_depth > 0
        when '[', '{'
          bracket_depth += 1
        when ']', '}'
          bracket_depth -= 1 if bracket_depth > 0
        when ','
          if paren_depth == 0 && bracket_depth == 0
            part = current.to_s.strip
            parts << part unless part.empty?
            current = String::Builder.new
            next
          end
        end

        current << ch
      end

      part = current.to_s.strip
      parts << part unless part.empty?
      parts
    end

    private def collect_python_collection_assignment(lines : Array(::String), start_index : Int32, line : ::String) : ::String
      return line unless line.includes?("[") || line.includes?("(")

      pieces = [line]
      depth = python_paren_delta(line) + python_bracket_delta(line)
      i = start_index + 1
      while i < lines.size && depth > 0
        pieces << lines[i]
        depth += python_paren_delta(lines[i]) + python_bracket_delta(lines[i])
        i += 1
      end

      pieces.join(" ")
    end

    private def clone_path_api_instances(path_api_instances : Hash(::String, Hash(::String, ::String))) : Hash(::String, Hash(::String, ::String))
      cloned = Hash(::String, Hash(::String, ::String)).new
      path_api_instances.each do |path, api_instances|
        cloned[path] = api_instances.dup
      end

      cloned
    end

    private def apply_nested_blueprint_prefixes(path_api_instances : Hash(::String, Hash(::String, ::String)),
                                                own_api_instances : Hash(::String, Hash(::String, ::String)),
                                                blueprint_mounts : Hash(::String, Array(Tuple(::String, ::String, ::String))))
      blueprint_mounts.each do |path, mounts|
        api_instances = path_api_instances[path]?
        next unless api_instances

        own_prefixes = own_api_instances[path]? || api_instances
        changed = true
        # Bound the fixpoint loop: an acyclic mount graph converges in at most
        # `mounts.size` propagation passes. A circular mount (A registers B and
        # B registers A) would otherwise grow the prefix every pass and never
        # converge -> infinite loop + unbounded memory on cyclic input.
        iterations = 0
        max_iterations = mounts.size + 1
        while changed && iterations < max_iterations
          iterations += 1
          changed = false
          mounts.each do |mount|
            parent_name, child_name, mount_prefix = mount
            next unless api_instances.has_key?(child_name)

            parent_prefix = api_instances[parent_name]? || ""
            child_own_prefix = own_prefixes[child_name]? || ""
            resolved_prefix = File.join(parent_prefix, mount_prefix, child_own_prefix)
            next if api_instances[child_name] == resolved_prefix

            api_instances[child_name] = resolved_prefix
            changed = true
          end
        end
      end
    end

    private def find_function_def(lines : Array(::String), function_name : ::String) : Int32?
      # Compile once per call; an interpolated literal inside the loop
      # would be recompiled on every line.
      def_re = /^\s*(?:async\s+)?def\s+#{Regex.escape(function_name)}\s*\(/
      lines.each_with_index do |line, index|
        if line.match(def_re)
          return index
        end
      end

      nil
    end

    # Locate `class <name>(...):` in a file's lines (-1 when absent).
    private def find_python_class_def(class_lines : Array(::String), class_name : ::String) : Int32
      class_prefix = "class #{class_name}"
      class_lines.each_with_index do |line, idx|
        stripped = line.lstrip
        if stripped.starts_with?(class_prefix) &&
           (stripped.size == class_prefix.size || stripped[class_prefix.size].in?('(', ':', ' ', '\t'))
          return idx
        end
      end
      -1
    end

    private def extract_class_declared_methods(class_lines : Array(::String), class_def_index : Int32, class_indent : Int32) : Array(::String)
      methods = [] of ::String
      i = class_def_index + 1
      while i < class_lines.size
        line = class_lines[i]
        stripped = line.strip
        unless stripped.empty?
          indent = line.size - line.lstrip.size
          break if indent <= class_indent

          if stripped.match(/^methods\s*=/)
            declaration = collect_python_collection_assignment(class_lines, i, line)
            declaration.scan(/['"]([A-Za-z]+)['"]/) do |m|
              method = m[1].upcase
              methods << method if PythonEngine::HTTP_METHODS.any? { |known| known.upcase == method }
            end
            break
          end
        end
        i += 1
      end

      methods.uniq
    end
  end
end
