require "../../../models/analyzer"
require "uri"

module Analyzer::Specification
  # TypeSpec (https://typespec.io) is Microsoft's OpenAPI-first IDL — `.tsp`
  # files describe operations with `@route` / `@get` / `@post` / ... decorators
  # that compose along namespace + interface scopes. This analyzer is a
  # line/block parser (not a full TypeSpec compiler): it walks balanced braces,
  # buffers decorators across newlines, and emits one endpoint per operation.
  class TypeSpec < Analyzer
    HTTP_VERB_DECORATORS = {"get", "post", "put", "patch", "delete", "head", "options"}

    def analyze
      locator = CodeLocator.instance
      typespec_files = locator.all("typespec-spec")

      if typespec_files.is_a?(Array(String))
        typespec_files.each do |path|
          next unless File.exists?(path)
          details = Details.new(PathInfo.new(path))
          content = read_file_content(path)
          process_file(content, details, path)
        end
      end

      @result
    end

    def push_endpoint(endpoint : Endpoint)
      @result << endpoint
    end

    private def process_file(content : String, details : Details, source : String)
      stripped = strip_comments(content)
      base_path = extract_server_path(stripped)
      Walker.new(stripped, self, details, source, base_path, @logger).walk
    rescue e
      @logger.debug "Exception while parsing TypeSpec: #{source}"
      @logger.debug_sub e
    end

    # Removes `//` line comments and `/* */` block comments. String literals are
    # preserved as-is so `//` inside a string isn't treated as a comment.
    private def strip_comments(s : String) : String
      io = String::Builder.new
      i = 0
      size = s.size
      while i < size
        c = s[i]
        if c == '/' && i + 1 < size && s[i + 1] == '/'
          while i < size && s[i] != '\n'
            i += 1
          end
        elsif c == '/' && i + 1 < size && s[i + 1] == '*'
          i += 2
          while i + 1 < size && !(s[i] == '*' && s[i + 1] == '/')
            i += 1
          end
          i += 2 if i + 1 < size
        elsif c == '"'
          io << c
          i += 1
          while i < size && s[i] != '"'
            if s[i] == '\\' && i + 1 < size
              io << s[i]
              i += 1
            end
            io << s[i]
            i += 1
          end
          if i < size
            io << s[i]
            i += 1
          end
        else
          io << c
          i += 1
        end
      end
      io.to_s
    end

    # TypeSpec `@server("https://api.example.com", "...")` at namespace level.
    # Mirror OAS3/RAML: keep only the URL path so endpoints render relative.
    private def extract_server_path(content : String) : String
      m = content.match(/@server\s*\(\s*"([^"]+)"/)
      return "" unless m
      url = m[1]
      return "" if url.empty?
      if url.starts_with?("http")
        begin
          uri = URI.parse(url)
          return (uri.path || "").rstrip('/')
        rescue
          return ""
        end
      end
      url.rstrip('/')
    end

    class Walker
      alias Decorator = Tuple(String, String?)

      HTTP_VERB_DECORATORS = {"get", "post", "put", "patch", "delete", "head", "options"}

      def initialize(@text : String, @analyzer : TypeSpec, @details : Details, @source : String, base_path : String, @logger : NoirLogger)
        @route_stack = [base_path]
        @interface_method = nil.as(String?)
      end

      def walk
        parse_block(0, @text.size, in_interface: false)
      end

      # Parses a sequence of statements between [pos, stop). Statements at this
      # level can introduce new scopes (namespace/interface) or declare an
      # operation. Decorators preceding a statement are buffered and consumed
      # when the statement's head keyword is found.
      private def parse_block(pos : Int32, stop : Int32, in_interface : Bool) : Int32
        decorators = [] of Decorator
        while pos < stop
          pos = skip_ws(pos, stop)
          break if pos >= stop
          c = @text[pos]

          case c
          when '@'
            pos, dec = read_decorator(pos + 1, stop)
            decorators << dec
            next
          when ';'
            pos += 1
            decorators.clear
            next
          when '}'
            return pos
          end

          ident_start = pos
          while pos < stop && (@text[pos].ascii_alphanumeric? || @text[pos] == '_')
            pos += 1
          end
          ident = @text[ident_start...pos]

          if ident.empty?
            pos += 1
            next
          end

          case ident
          when "namespace"
            pos = parse_namespace(pos, stop, decorators)
            decorators.clear
          when "interface"
            pos = parse_interface(pos, stop, decorators)
            decorators.clear
          when "op"
            pos = parse_op_with_keyword(pos, stop, decorators)
            decorators.clear
          when "import", "using"
            pos = skip_to_semicolon(pos, stop)
            pos += 1 if pos < stop
            decorators.clear
          when "model", "scalar", "enum", "union", "alias", "extends"
            pos = skip_statement(pos, stop)
            decorators.clear
          else
            if in_interface
              pos = parse_op_shorthand(pos, stop, ident, decorators)
              decorators.clear
            else
              pos = skip_statement(pos, stop)
              decorators.clear
            end
          end
        end
        pos
      end

      private def parse_namespace(pos : Int32, stop : Int32, decorators : Array(Decorator)) : Int32
        pos = skip_ws(pos, stop)
        while pos < stop && (@text[pos].ascii_alphanumeric? || @text[pos] == '_' || @text[pos] == '.')
          pos += 1
        end
        pos = skip_ws(pos, stop)

        route_extra = route_from(decorators)
        @route_stack << join_route(@route_stack.last, route_extra)

        if pos < stop && @text[pos] == '{'
          body_end = find_matching(pos, stop, '{', '}')
          parse_block(pos + 1, body_end - 1, in_interface: false)
          @route_stack.pop
          body_end
        elsif pos < stop && @text[pos] == ';'
          # file-scoped namespace: everything after stays under this route, so
          # we intentionally do not pop @route_stack.
          pos + 1
        else
          @route_stack.pop
          pos
        end
      end

      private def parse_interface(pos : Int32, stop : Int32, decorators : Array(Decorator)) : Int32
        pos = skip_ws(pos, stop)
        while pos < stop && (@text[pos].ascii_alphanumeric? || @text[pos] == '_')
          pos += 1
        end
        # Skip optional generics, `extends ...` clauses, etc.
        while pos < stop && @text[pos] != '{' && @text[pos] != ';'
          pos += 1
        end

        route_extra = route_from(decorators)
        @route_stack << join_route(@route_stack.last, route_extra)
        prior_method = @interface_method
        @interface_method = method_from(decorators)

        if pos < stop && @text[pos] == '{'
          body_end = find_matching(pos, stop, '{', '}')
          parse_block(pos + 1, body_end - 1, in_interface: true)
          @route_stack.pop
          @interface_method = prior_method
          return body_end
        end
        @route_stack.pop
        @interface_method = prior_method
        pos + (pos < stop ? 1 : 0)
      end

      # `op` keyword consumed; expect `name(...) : Type;` or `name is Other;`.
      private def parse_op_with_keyword(pos : Int32, stop : Int32, decorators : Array(Decorator)) : Int32
        pos = skip_ws(pos, stop)
        name_start = pos
        while pos < stop && (@text[pos].ascii_alphanumeric? || @text[pos] == '_')
          pos += 1
        end
        name = @text[name_start...pos]
        return pos if name.empty?
        consume_op_signature(pos, stop, name, decorators)
      end

      # Interface shorthand: identifier already consumed as the operation name.
      private def parse_op_shorthand(pos : Int32, stop : Int32, name : String, decorators : Array(Decorator)) : Int32
        consume_op_signature(pos, stop, name, decorators)
      end

      private def consume_op_signature(pos : Int32, stop : Int32, name : String, decorators : Array(Decorator)) : Int32
        pos = skip_ws(pos, stop)
        # Skip generics: op create<T>(...)
        if pos < stop && @text[pos] == '<'
          pos = find_matching(pos, stop, '<', '>')
          pos = skip_ws(pos, stop)
        end

        unless pos < stop && @text[pos] == '('
          # `op X is Y;` and similar — skip without emitting.
          return skip_to_semicolon(pos, stop) + 1
        end

        args_start = pos + 1
        args_end = find_matching(pos, stop, '(', ')')
        args = @text[args_start...(args_end - 1)]
        pos = args_end

        pos = skip_to_semicolon(pos, stop)
        pos += 1 if pos < stop

        build_endpoint(name, args, decorators)
        pos
      end

      private def build_endpoint(name : String, args_text : String, decorators : Array(Decorator))
        route_extra = route_from(decorators)
        full_path = join_route(@route_stack.last, route_extra)
        full_path = "/" if full_path.empty?

        method = method_from(decorators) || @interface_method
        return unless method

        params = parse_params(args_text, full_path, method)
        @analyzer.push_endpoint(Endpoint.new(full_path, method.upcase, params, @details))
      rescue e
        @logger.debug "Exception while emitting TypeSpec op #{name} in #{@source}"
        @logger.debug_sub e
      end

      private def parse_params(args_text : String, route_path : String, method : String) : Array(Param)
        params = [] of Param
        return params if args_text.strip.empty?

        split_top_level(args_text, ',').each do |raw|
          p = parse_param(raw, route_path, method)
          params << p if p
        end
        params
      end

      private def parse_param(raw : String, route_path : String, method : String) : Param?
        s = raw.strip
        return if s.empty?

        explicit_type = nil.as(String?)
        # For `@header("X-Trace-Id") name: T`, TypeSpec lets the decorator's
        # first string literal override the wire name. Capture it so the param
        # is recorded under the HTTP header name, not the Crystal-side variable.
        decorator_name_override = nil.as(String?)
        loop do
          break unless s.starts_with?('@')
          s = s[1..]
          name_end = 0
          while name_end < s.size && (s[name_end].ascii_alphanumeric? || s[name_end] == '_')
            name_end += 1
          end
          dec_name = s[0...name_end]
          s = s[name_end..].lstrip
          if s.starts_with?('(')
            close = find_matching_str(s, 0, '(', ')')
            dec_args = s[1...(close - 1)]
            s = s[close..].lstrip
            if decorator_name_override.nil? && classifies_param?(dec_name)
              if m = dec_args.match(/^\s*"([^"]+)"/)
                decorator_name_override = m[1]
              end
            end
          end
          explicit_type ||= classify_decorator(dec_name)
        end

        return if s.empty?

        # Backtick-quoted identifiers (e.g. `` `X-Trace-Id` ``) — read literal name.
        if s.starts_with?('`')
          close = s.index('`', 1)
          return unless close
          name = s[1...close]
        else
          name_end = 0
          while name_end < s.size && (s[name_end].ascii_alphanumeric? || s[name_end] == '_')
            name_end += 1
          end
          name = s[0...name_end]
        end
        return if name.empty?

        final_name = decorator_name_override || name
        param_type = explicit_type || infer_param_type(name, route_path, method)
        Param.new(final_name, "", param_type)
      end

      private def classifies_param?(dec_name : String) : Bool
        case dec_name.downcase
        when "body", "bodyroot", "bodyignore", "query", "header", "path", "cookie", "formdata", "form"
          true
        else
          false
        end
      end

      private def classify_decorator(dec_name : String) : String?
        case dec_name.downcase
        when "body", "bodyroot", "bodyignore"
          "json"
        when "query"
          "query"
        when "header"
          "header"
        when "path"
          "path"
        when "cookie"
          "cookie"
        when "formdata", "form"
          "form"
        end
      end

      # No decorator: TypeSpec infers path params from the route template, then
      # falls back to query for GET-like methods and body for write methods.
      private def infer_param_type(name : String, route_path : String, method : String) : String
        return "path" if route_path.includes?("{#{name}}")
        case method.downcase
        when "get", "head", "delete"
          "query"
        else
          "json"
        end
      end

      private def route_from(decorators : Array(Decorator)) : String
        decorators.each do |dec|
          name, args = dec
          next unless name == "route"
          next unless args
          m = args.match(/"([^"]*)"/)
          return m[1] if m
        end
        ""
      end

      private def method_from(decorators : Array(Decorator)) : String?
        decorators.each do |dec|
          name, _ = dec
          return name if HTTP_VERB_DECORATORS.includes?(name.downcase)
        end
        nil
      end

      private def join_route(parent : String, segment : String) : String
        return parent if segment.empty?
        parent_clean = parent.rstrip('/')
        seg_clean = segment.starts_with?('/') ? segment[1..] : segment
        seg_clean.empty? ? parent_clean : "#{parent_clean}/#{seg_clean}"
      end

      private def read_decorator(pos : Int32, stop : Int32) : {Int32, Decorator}
        name_start = pos
        while pos < stop && (@text[pos].ascii_alphanumeric? || @text[pos] == '_' || @text[pos] == '.')
          pos += 1
        end
        name = @text[name_start...pos]
        args = nil.as(String?)
        pos = skip_ws(pos, stop)
        if pos < stop && @text[pos] == '('
          args_start = pos + 1
          pos = find_matching(pos, stop, '(', ')')
          args = @text[args_start...(pos - 1)]
        end
        {pos, {name, args}}
      end

      private def skip_ws(pos : Int32, stop : Int32) : Int32
        while pos < stop && @text[pos].ascii_whitespace?
          pos += 1
        end
        pos
      end

      private def find_matching(pos : Int32, stop : Int32, open : Char, close : Char) : Int32
        depth = 0
        in_string = false
        while pos < stop
          c = @text[pos]
          if in_string
            if c == '\\' && pos + 1 < stop
              pos += 2
              next
            elsif c == '"'
              in_string = false
            end
          else
            if c == '"'
              in_string = true
            elsif c == open
              depth += 1
            elsif c == close
              depth -= 1
              return pos + 1 if depth == 0
            end
          end
          pos += 1
        end
        pos
      end

      private def find_matching_str(s : String, pos : Int32, open : Char, close : Char) : Int32
        depth = 0
        in_string = false
        while pos < s.size
          c = s[pos]
          if in_string
            if c == '\\' && pos + 1 < s.size
              pos += 2
              next
            elsif c == '"'
              in_string = false
            end
          else
            if c == '"'
              in_string = true
            elsif c == open
              depth += 1
            elsif c == close
              depth -= 1
              return pos + 1 if depth == 0
            end
          end
          pos += 1
        end
        pos
      end

      private def skip_to_semicolon(pos : Int32, stop : Int32) : Int32
        depth = 0
        in_string = false
        while pos < stop
          c = @text[pos]
          if in_string
            if c == '\\' && pos + 1 < stop
              pos += 2
              next
            elsif c == '"'
              in_string = false
            end
          else
            case c
            when '"'
              in_string = true
            when '(', '{', '[', '<'
              depth += 1
            when ')', '}', ']', '>'
              depth -= 1 if depth > 0
            when ';'
              return pos if depth == 0
            end
          end
          pos += 1
        end
        pos
      end

      # Walks until the current statement ends. A statement either closes a
      # `{...}` block (`model X { ... }`, no trailing `;` needed in TypeSpec) or
      # terminates at `;` at depth 0. A `}` met while already at depth 0 belongs
      # to an outer scope — return without consuming it so the caller can close.
      private def skip_statement(pos : Int32, stop : Int32) : Int32
        depth = 0
        in_string = false
        while pos < stop
          c = @text[pos]
          if in_string
            if c == '\\' && pos + 1 < stop
              pos += 2
              next
            elsif c == '"'
              in_string = false
            end
          else
            case c
            when '"'
              in_string = true
            when '{', '(', '['
              depth += 1
            when '}', ')', ']'
              return pos if depth == 0
              depth -= 1
              return pos + 1 if depth == 0 && c == '}'
            when ';'
              return pos + 1 if depth == 0
            end
          end
          pos += 1
        end
        pos
      end

      private def split_top_level(text : String, delim : Char) : Array(String)
        parts = [] of String
        depth = 0
        in_string = false
        start = 0
        i = 0
        while i < text.size
          c = text[i]
          if in_string
            if c == '\\' && i + 1 < text.size
              i += 2
              next
            elsif c == '"'
              in_string = false
            end
          else
            case c
            when '"'
              in_string = true
            when '(', '{', '[', '<'
              depth += 1
            when ')', '}', ']', '>'
              depth -= 1 if depth > 0
            else
              if c == delim && depth == 0
                parts << text[start...i]
                start = i + 1
              end
            end
          end
          i += 1
        end
        parts << text[start..] if start < text.size
        parts
      end
    end
  end
end
