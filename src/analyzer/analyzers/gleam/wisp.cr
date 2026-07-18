require "../../../models/analyzer"
require "./gleam_helper"
require "set"

module Analyzer::Gleam
  # Wisp has no route table — routing is a `case` over the split path,
  # and the verb comes either from a second subject in the same `case` or
  # from the handler it delegates to. All four shapes are common in real
  # apps:
  #
  #     case wisp.path_segments(req) {                  # path only
  #       ["users", id] -> user(req, id)
  #     }
  #
  #     case wisp.path_segments(req), req.method {      # path, method
  #       ["api", "teams"], http.Post -> create_team(req)
  #     }
  #
  #     case req.method, wisp.path_segments(req) {      # method, path
  #       Get, ["members"] -> members.list(req)
  #     }
  #
  #     let path = wisp.path_segments(req)              # via let bindings
  #     let method = req.method
  #     case method, path {
  #       Get, [] -> home.render(req)
  #     }
  #
  # Rather than assume an order, the subject is parsed to learn which
  # comma position holds the path and which holds the method, and each
  # arm is then read against those positions. When the arm carries no
  # verb the handler it calls is followed (`resolve_handler`) to find a
  # `case req.method` or a `wisp.require_method`.
  class Wisp < Analyzer
    CASE_KEYWORD = /\bcase\b/
    PATH_SOURCE  = /\bpath_segments\s*\(/
    # `let path = wisp.path_segments(req)` / `let method = req.method`.
    # Apps that bind these before the `case` would otherwise leave the
    # subject looking like two bare identifiers.
    PATH_BINDING   = /\blet\s+([a-z_][A-Za-z0-9_]*)\s*=[^\n]*\bpath_segments\s*\(/
    METHOD_BINDING = /\blet\s+([a-z_][A-Za-z0-9_]*)\s*=\s*[a-z_][A-Za-z0-9_]*\.method\b/
    METHOD_SOURCE  = /\.method\b/

    METHOD_CASE    = /\bcase\s+[A-Za-z_][A-Za-z0-9_]*\.method\s*\{/
    REQUIRE_METHOD = /require_method\s*\(\s*[^,)]+,\s*(?:[a-z_][A-Za-z0-9_]*\.)?([A-Z][A-Za-z0-9_]*)/
    METHOD_TOKEN   = /\A(?:[a-z_][A-Za-z0-9_]*\.)?([A-Z][A-Za-z0-9_]*)\z/

    FUNCTION_DEF = /^\s*(?:pub\s+)?fn\s+([a-z_][A-Za-z0-9_]*)\s*\(/
    IMPORT_LINE  = /^\s*import\s+([a-z_][A-Za-z0-9_\/]*)(?:\s*\.\s*\{[^}]*\})?(?:\s+as\s+([a-z_][A-Za-z0-9_]*))?/

    CALL_REGEX = /(?:\b([a-z_][A-Za-z0-9_]*)\s*\.\s*)?\b([a-z_][A-Za-z0-9_]*)\s*\(/

    # Calls into the standard library and wisp itself are responses and
    # helpers, never route handlers.
    IGNORED_CALL_MODULES = Set{
      "wisp", "gleam", "http", "request", "response", "io", "list",
      "string", "int", "float", "result", "option", "json", "dict",
      "bool", "bit_array", "dynamic", "decode", "uri", "bytes_tree",
      "string_tree", "mist", "case", "fn", "use", "let",
    }

    # `_ -> wisp.method_not_allowed([Get, Post])` and
    # `_, _ -> wisp.not_found()` are the fallthrough arms every wisp
    # router ends with. They match a path but serve no endpoint.
    NON_ROUTE_BODY = /\A\s*(?:wisp\.)?(?:method_not_allowed|not_found|bad_request|unprocessable_entity|internal_server_error|handle_request\s*\(\s*\))/

    HTTP_METHODS = {
      "Get"     => "GET",
      "Post"    => "POST",
      "Put"     => "PUT",
      "Patch"   => "PATCH",
      "Delete"  => "DELETE",
      "Head"    => "HEAD",
      "Options" => "OPTIONS",
      "Trace"   => "TRACE",
      "Connect" => "CONNECT",
    }

    SERVE_STATIC = /wisp\.serve_static\s*\(/
    FORM_REGEX   = /wisp\.require_form\s*\(/
    JSON_REGEX   = /wisp\.require_json\s*\(/
    STRING_BODY  = /wisp\.require_(?:string|bit_array)_body\s*\(/
    COOKIE_REGEX = /wisp\.get_cookie\s*\(\s*[^,]+,\s*"([^"]+)"/
    # 2-arg `request.get_header(req, "accept")` and the piped 1-arg
    # `|> request.get_header("accept")` are both idiomatic.
    HEADER_REGEX = /\bget_header\s*\(\s*(?:[^,"()]+,\s*)?"([^"]+)"/
    # `list.key_find(formdata.values, "title")` — the binder is named
    # `formdata`, `form`, … so match any receiver.
    FORM_FIELD_REGEX = /key_find\s*\(\s*[A-Za-z_][A-Za-z0-9_]*\.(?:values|files)\s*,\s*"([^"]+)"/
    # A `wisp.require_json` body is decoded elsewhere; `decode.field` is
    # where the field names actually appear.
    JSON_FIELD_REGEX = /\bfield\s*\(\s*"([^"]+)"/

    # Verbs that can carry a request body.
    BODY_VERBS = Set{"POST", "PUT", "PATCH", "ANY"}

    # Depth limit for following a route arm through handler functions to
    # the `case req.method` that names its verb.
    MAX_RESOLVE_DEPTH = 3
    # A `case` subject spans at most a handful of lines even when the
    # formatter wraps it.
    MAX_SUBJECT_LINES = 8

    record Resolved, methods : Array(String), params : Array(Param), mount : Bool

    @module_index = {} of Tuple(String, String) => String
    @functions = {} of String => Hash(String, String)
    @imports = {} of String => Hash(String, String)
    @contents = {} of String => String

    def analyze
      gleam_files = get_files_by_extension(".gleam").reject! { |path| File.directory?(path) }
      return @result if gleam_files.empty?

      build_module_index(gleam_files)

      gleam_files.each do |path|
        content = file_content(path)
        next unless content.matches?(PATH_SOURCE)
        next unless route_file?(path, content)

        process_file(path, content)
      end

      @result
    end

    # Mist apps route with the same `case request.path_segments(req)`
    # shape but belong to the Mist analyzer. Wisp owns a file only when
    # wisp is actually in play.
    private def route_file?(_path : String, content : String) : Bool
      content.includes?("wisp")
    end

    private def file_content(path : String) : String
      @contents[path] ||= Helper.strip_gleam_comments(read_file_content(path))
    end

    # A Gleam module's name is its path under `src/` (or `test/`) minus
    # the extension: `src/app/web/users.gleam` is `app/web/users`, which
    # is what `import app/web/users` refers to.
    private def build_module_index(files : Array(String))
      files.each do |path|
        module_name = gleam_module_name(path)
        next unless module_name
        @module_index[{configured_base_for(path), module_name}] ||= path
      end
    end

    private def gleam_module_name(path : String) : String?
      normalized = path.gsub('\\', '/')
      return unless normalized.ends_with?(".gleam")

      relative = if idx = (normalized.rindex("/src/") || normalized.rindex("/test/"))
                   normalized[(normalized.index('/', idx + 1) || idx) + 1..]
                 elsif normalized.starts_with?("src/") || normalized.starts_with?("test/")
                   normalized.split('/', 2)[1]
                 else
                   File.basename(normalized)
                 end

      relative[0...-".gleam".size]
    end

    private def process_file(path : String, content : String)
      lines = content.lines
      path_vars = binding_names(content, PATH_BINDING)
      method_vars = binding_names(content, METHOD_BINDING)

      lines.each_with_index do |line, idx|
        next unless line.matches?(CASE_KEYWORD)

        located = locate_case(lines, idx)
        next unless located

        subject = subject_layout(located[:subject], path_vars, method_vars)
        next unless subject

        block_end = block_end_line(lines, located[:block_line])
        next unless block_end

        each_arm(lines, located[:block_line], block_end) do |pattern, body, arm_line|
          emit_arm(path, pattern, body, arm_line, subject)
        end
      end
    end

    private def binding_names(content : String, regex : Regex) : Set(String)
      names = Set(String).new
      content.scan(regex) { |m| names << m[1] }
      names
    end

    # Finds the `{` that opens a `case`'s arms, which is not simply the
    # first `{` after the keyword — the subject may itself be a block:
    #
    #     case
    #       { req |> wisp.path_segments() }
    #     {
    #       [r] -> …
    #
    # Each balanced `{…}` that is followed by another `{` was a subject
    # block; the one that isn't opens the arms.
    private def locate_case(lines : Array(String), case_idx : Int32) : NamedTuple(subject: String, block_line: Int32)?
      keyword = lines[case_idx].index(CASE_KEYWORD)
      return unless keyword

      window_end = Math.min(case_idx + MAX_SUBJECT_LINES, lines.size - 1)
      window = lines[case_idx..window_end].join("\n")
      pos = keyword + "case".size

      while brace = next_top_level_brace(window, pos)
        span = Helper.balanced_span(window, brace)
        unless span
          # Never closes inside the window, so it is the arms block.
          return {subject: window[pos...brace], block_line: case_idx + count_newlines(window, brace)}
        end

        after = brace + span.size
        rest = window[after..]?
        if rest && rest.lstrip.starts_with?('{')
          pos = after
          next
        end

        return {subject: window[(keyword + "case".size)...brace], block_line: case_idx + count_newlines(window, brace)}
      end

      nil
    end

    private def next_top_level_brace(text : String, from : Int32) : Int32?
      depth = 0
      in_string = false
      i = from
      chars = text.chars

      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\'
            i += 2
            next
          end
          in_string = false if c == '"'
          i += 1
          next
        end

        case c
        when '"'      then in_string = true
        when '(', '[' then depth += 1
        when ')', ']' then depth -= 1
        when '{'
          return i if depth == 0
          depth += 1
        when '}' then depth -= 1
        end

        i += 1
      end

      nil
    end

    private def count_newlines(text : String, up_to : Int32) : Int32
      count = 0
      i = 0
      text.each_char do |c|
        break if i >= up_to
        count += 1 if c == '\n'
        i += 1
      end
      count
    end

    private def block_end_line(lines : Array(String), block_line : Int32) : Int32?
      depth = 0
      opened = false

      i = block_line
      while i < lines.size
        depth += brace_delta(lines[i])
        opened = true if depth > 0
        return i if opened && depth <= 0
        i += 1
      end

      nil
    end

    # Which comma position of the `case` subject holds the path and which
    # holds the method. Returns nil when no position is a path, i.e. this
    # `case` isn't routing.
    private def subject_layout(subject : String,
                               path_vars : Set(String),
                               method_vars : Set(String)) : NamedTuple(path: Int32, method: Int32?)?
      parts = Helper.split_pattern_segments(subject)
      return if parts.empty?

      path_index = nil.as(Int32?)
      method_index = nil.as(Int32?)

      parts.each_with_index do |part, index|
        if part.matches?(PATH_SOURCE) || path_vars.any? { |name| references?(part, name) }
          path_index ||= index
        elsif part.matches?(METHOD_SOURCE) || method_vars.any? { |name| references?(part, name) }
          method_index ||= index
        end
      end

      return unless path_index
      {path: path_index, method: method_index}
    end

    private def references?(text : String, name : String) : Bool
      idx = 0
      while found = text.index(name, idx)
        before = found == 0 ? nil : text[found - 1]
        after_idx = found + name.size
        after = after_idx < text.size ? text[after_idx] : nil
        boundary_before = before.nil? || !(before.alphanumeric? || before == '_')
        boundary_after = after.nil? || !(after.alphanumeric? || after == '_')
        return true if boundary_before && boundary_after
        idx = found + 1
      end
      false
    end

    private def brace_delta(line : String) : Int32
      delta = 0
      in_string = false
      chars = line.chars
      i = 0
      while i < chars.size
        c = chars[i]
        if in_string
          if c == '\\'
            i += 2
            next
          end
          in_string = false if c == '"'
          i += 1
          next
        end
        case c
        when '"' then in_string = true
        when '{' then delta += 1
        when '}' then delta -= 1
        end
        i += 1
      end
      delta
    end

    # Yields `{pattern, body, line}` per arm at the top level of the case
    # block. Depth tracking keeps a nested `case req.method { Get -> … }`
    # inside an arm body from reading as a new arm, and keeps a
    # `gleam format`-wrapped body attached to its pattern.
    private def each_arm(lines : Array(String), block_line : Int32, end_line : Int32, &)
      depth = 0
      pending_pattern = nil.as(String?)
      pending_line = 0
      pending_body = [] of String

      i = block_line
      while i <= end_line
        line = lines[i]
        line_depth = depth
        depth += brace_delta(line)

        if i > block_line && line_depth == 1 && (arrow = top_level_arrow(line))
          if pattern = pending_pattern
            yield pattern, pending_body.join("\n"), pending_line
          end
          pending_pattern = line[0...arrow].strip
          pending_line = i + 1
          pending_body = [line[(arrow + 2)..]]
        elsif pending_pattern
          pending_body << line
        end

        i += 1
      end

      if pattern = pending_pattern
        yield pattern, pending_body.join("\n"), pending_line
      end
    end

    private def top_level_arrow(line : String) : Int32?
      depth = 0
      in_string = false
      chars = line.chars
      i = 0
      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\'
            i += 2
            next
          end
          in_string = false if c == '"'
          i += 1
          next
        end

        case c
        when '"'           then in_string = true
        when '[', '(', '{' then depth += 1
        when ']', ')', '}' then depth -= 1
        when '-'
          return i if depth == 0 && chars[i + 1]? == '>'
        end

        i += 1
      end

      nil
    end

    private def emit_arm(path : String,
                         pattern : String,
                         body : String,
                         line : Int32,
                         subject : NamedTuple(path: Int32, method: Int32?))
      return if body.strip.matches?(NON_ROUTE_BODY)

      # The handler chain is the same for every alternative of this arm,
      # and its params are needed either way, so resolve it once.
      resolved = resolve_handler(body, path, 0)

      # `["a"] | ["b"] -> …` is one arm serving two paths.
      Helper.split_alternatives(pattern).each do |alternative|
        parts = Helper.split_pattern_segments(alternative)
        path_pattern = parts[subject[:path]]?
        next unless path_pattern

        segments = list_pattern_segments(path_pattern)
        next unless segments

        url, path_params = Helper.parse_segments(segments)

        methods = [] of String
        if method_index = subject[:method]
          if token = parts[method_index]?
            if m = token.match(METHOD_TOKEN)
              if verb = HTTP_METHODS[m[1]]?
                methods << verb
              end
            end
          end
        end

        if methods.empty?
          # A `["admin", ..] -> admin.router(req)` mount delegates to a
          # sub-router that matches the same absolute paths itself, so
          # emitting the prefix here would only add a phantom wildcard.
          next if resolved.mount
          methods = resolved.methods
        end

        methods = ["ANY"] if methods.empty?

        handler_params = resolved.params

        methods.each do |method|
          params = path_params.dup
          seen = params.map(&.name).to_set
          handler_params.each do |param|
            next if param.param_type == "path" && seen.includes?(param.name)
            # Params are collected across the whole handler chain, so a
            # module serving both GET and POST would otherwise hang the
            # POST form fields off its GET route.
            next if param.param_type == "body" && !BODY_VERBS.includes?(method)
            params << param
          end

          details = Details.new(PathInfo.new(path, line))
          @result << Endpoint.new(url, method, params, details)
        end
      end
    end

    # A routing pattern is a list of segments. `_` is the fallthrough,
    # and anything else (a guard, a constructor) isn't a path.
    private def list_pattern_segments(pattern : String) : Array(String)?
      text = pattern.strip
      return unless text.starts_with?('[') && text.ends_with?(']')
      Helper.split_pattern_segments(text[1...-1])
    end

    private def resolve_handler(body : String,
                                path : String,
                                depth : Int32,
                                visited : Set(Tuple(String, String)) = Set(Tuple(String, String)).new) : Resolved
      methods = [] of String
      params = extract_params(body)
      seen = Set(String).new
      mount = false

      collect_methods(body, methods, seen)

      if depth < MAX_RESOLVE_DEPTH
        each_delegate_call(body, path) do |target_body, target_path, target_name|
          # The delegate routes on its own — this arm is a mount point,
          # and the sub-router matches the same absolute paths itself.
          if methods.empty? && target_body.matches?(PATH_SOURCE)
            mount = true
            break
          end

          next unless visited.add?({target_path, target_name})

          nested = resolve_handler(target_body, target_path, depth + 1, visited)
          # Verbs come from the shallowest handler that names any, so a
          # sibling call can't contribute a verb this route never serves.
          # Params keep accumulating, because the field reads sit one
          # level below the `case req.method` that resolved the verb.
          nested.methods.each { |verb| methods << verb if seen.add?(verb) } if methods.empty?
          params.concat(nested.params)
        end
      end

      Resolved.new(methods, dedupe(params), mount)
    end

    private def collect_methods(body : String, methods : Array(String), seen : Set(String))
      # `wisp.serve_static` is the static-file handler; it only ever
      # serves GET and HEAD, and lives in wisp so there is nothing to
      # follow.
      if body.matches?(SERVE_STATIC)
        methods << "GET" if seen.add?("GET")
        return
      end

      body.scan(REQUIRE_METHOD) do |m|
        if verb = HTTP_METHODS[m[1]]?
          methods << verb if seen.add?(verb)
        end
      end

      return unless body.matches?(METHOD_CASE)

      # Inside `case req.method { … }` each constructor left of an arrow
      # is a verb this handler serves.
      body.scan(/(?:^|\n)\s*(?:[a-z_][A-Za-z0-9_]*\.)?([A-Z][A-Za-z0-9_]*)\s*->/) do |m|
        if verb = HTTP_METHODS[m[1]]?
          methods << verb if seen.add?(verb)
        end
      end
    end

    private def each_delegate_call(body : String, path : String, &)
      body.scan(CALL_REGEX) do |m|
        module_alias = m[1]?
        name = m[2]

        if module_alias
          next if IGNORED_CALL_MODULES.includes?(module_alias)
          target_path = resolve_import(path, module_alias)
          next unless target_path
          if target_body = functions_for(target_path)[name]?
            yield target_body, target_path, name
          end
        else
          next if IGNORED_CALL_MODULES.includes?(name)
          if target_body = functions_for(path)[name]?
            yield target_body, path, name
          end
        end
      end
    end

    private def resolve_import(path : String, module_alias : String) : String?
      imports_for(path)[module_alias]?.try do |module_name|
        @module_index[{configured_base_for(path), module_name}]?
      end
    end

    private def imports_for(path : String) : Hash(String, String)
      @imports[path] ||= begin
        table = {} of String => String
        file_content(path).each_line do |line|
          next unless m = line.match(IMPORT_LINE)
          module_name = m[1]
          # `import app/web/users` is referred to as `users`;
          # `import app/web/users as u` as `u`.
          table[m[2]? || module_name.split('/').last] = module_name
        end
        table
      end
    end

    # `name => body` for every function in the file.
    private def functions_for(path : String) : Hash(String, String)
      @functions[path] ||= begin
        table = {} of String => String
        lines = file_content(path).lines

        lines.each_with_index do |line, idx|
          next unless m = line.match(FUNCTION_DEF)
          name = m[1]
          next if table.has_key?(name)

          if block_end = block_end_line(lines, idx)
            table[name] = lines[idx..block_end].join("\n")
          end
        end

        table
      end
    end

    private def extract_params(body : String) : Array(Param)
      params = [] of Param

      # `wisp.require_form` / `require_json` say a body is read but not
      # what is in it; the field names show up in `list.key_find` and
      # `decode.field` calls, which often sit a function or two away. Both
      # are collected here and the placeholder is dropped later if any
      # named field turns up anywhere in the chain.
      body.scan(FORM_FIELD_REGEX) { |m| params << Param.new(m[1], "", "body") }
      body.scan(JSON_FIELD_REGEX) { |m| params << Param.new(m[1], "", "body") }

      if body.matches?(JSON_REGEX)
        params << Param.new("body", "JSON", "body")
      elsif body.matches?(FORM_REGEX)
        params << Param.new("body", "Form", "body")
      elsif body.matches?(STRING_BODY)
        params << Param.new("body", "", "body")
      end

      body.scan(HEADER_REGEX) { |m| params << Param.new(m[1], "", "header") }
      body.scan(COOKIE_REGEX) { |m| params << Param.new(m[1], "", "cookie") }

      params
    end

    private def dedupe(params : Array(Param)) : Array(Param)
      seen = Set(Tuple(String, String)).new
      unique = params.select { |param| seen.add?({param.name, param.param_type}) }

      # Once the real field names are known the "there is a body"
      # placeholder is just noise.
      named_body = unique.any? { |param| param.param_type == "body" && param.name != "body" }
      named_body ? unique.reject { |param| param.param_type == "body" && param.name == "body" } : unique
    end
  end
end
