require "../../../models/analyzer"

module Analyzer::Groovy
  # Grails follows a convention-over-configuration layout where each
  # controller class under `grails-app/controllers/` exposes its action
  # methods as URL endpoints. The default URL mapping is
  # `"/$controller/$action?/$id?(.$format)?"`, so we surface every
  # action method as `/<controller>/<action>` (the controller name is
  # the class name with the `Controller` suffix dropped and the first
  # letter lowercased).
  #
  # Two action styles are handled:
  #   * Method form:  `def show() { ... }`
  #   * Closure form: `def show = { ... }`  (legacy Grails)
  #
  # When the controller declares
  #   `static allowedMethods = [save: 'POST', update: ['PUT', 'PATCH']]`
  # those restrictions are honored; otherwise actions are emitted as
  # `GET` (the default Grails dispatch verb when no restriction is set).
  #
  # `grails-app/conf/UrlMappings.groovy` is also scanned for explicit
  # string-based mappings of the form
  #   `get '/api/users'(controller: 'user', action: 'list')`
  # which are surfaced as additional endpoints.
  class Grails < Analyzer
    DEFAULT_METHODS = ["GET"]
    HTTP_METHODS    = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]

    SKIP_ACTION_NAMES = %w[
      beforeInterceptor afterInterceptor afterView allowedMethods
      scaffold defaultAction errors response request params
    ]

    def analyze
      all_files.each do |path|
        next if File.directory?(path)
        next unless path.ends_with?(".groovy")

        content = read_file_content(path)

        if controller_path?(path)
          process_controller(path, content)
        end

        if url_mappings_path?(path)
          process_url_mappings(path, content)
        end
      end

      @result
    end

    private def controller_path?(path : String) : Bool
      path.includes?("/grails-app/controllers/")
    end

    private def url_mappings_path?(path : String) : Bool
      # Grails plugins ship their own `<Name>UrlMappings.groovy` files
      # alongside the canonical `UrlMappings.groovy`, so accept any basename
      # ending in `UrlMappings.groovy` — but only inside `grails-app/conf/`
      # so unrelated files with similar names are not picked up.
      return false unless path.includes?("/grails-app/conf/")
      File.basename(path).ends_with?("UrlMappings.groovy")
    end

    private def process_controller(path : String, content : String)
      cleaned = strip_groovy_comments(content)

      cleaned.scan(/((?:(?:public|protected|private|abstract|final|static)\s+)*)class\s+([A-Z][A-Za-z0-9_]*Controller)\b[^\{]*\{/) do |match|
        modifiers = match[1]
        class_name = match[2]
        match_end = match.end(0)
        match_start = match.begin(0)
        next unless match_end && match_start
        # Abstract base controllers are templates for subclasses, not
        # directly addressable endpoints — skip them.
        next if modifiers.includes?("abstract")

        body_info = extract_braced_block(cleaned, match_end - 1)
        next unless body_info
        body, body_start = body_info

        controller_name = controller_name_for(class_name)
        allowed_methods = parse_allowed_methods(body)
        actions = extract_actions(body)

        actions.each do |action|
          methods = allowed_methods[action[:name]]? || DEFAULT_METHODS
          line = line_for_offset(content, body_start + action[:offset])
          line = line_for_offset(content, match_start) if line <= 0
          methods.each do |verb|
            url = "/#{controller_name}/#{action[:name]}"
            details = Details.new(PathInfo.new(path, line))
            @result << Endpoint.new(url, verb, [] of Param, details)
          end
        end
      end
    end

    private def controller_name_for(class_name : String) : String
      base = class_name
      base = base[0...(base.size - "Controller".size)] if base.ends_with?("Controller")
      return class_name.downcase if base.empty?
      base[0].downcase.to_s + base[1..]
    end

    private def extract_actions(body : String) : Array(NamedTuple(name: String, offset: Int32))
      actions = [] of NamedTuple(name: String, offset: Int32)
      depth = 0
      in_string = false
      string_quote = '\0'
      i = 0

      while i < body.size
        c = body[i]

        if in_string
          if c == '\\' && i + 1 < body.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
          i += 1
          next
        when '{'
          depth += 1
          i += 1
          next
        when '}'
          depth -= 1 if depth > 0
          i += 1
          next
        else
          # fall through
        end

        if depth == 0
          rest = body[i..]
          # Method form: `def name(...)`
          # Closure form: `def name = { ... }` — explicitly require the
          # closure brace via lookahead so plain field assignments like
          # `def cache = [:]` or `def bookService = new BookService()`
          # are not mistaken for actions.
          m = rest.match(/\A(public\s+|protected\s+|private\s+)?def\s+([a-z_][A-Za-z0-9_]*)\s*(?:\(|=\s*(?=\{))/)
          if m
            modifier = m[1]?
            name = m[2]
            is_private = modifier && modifier.lstrip.starts_with?("private")
            unless is_private || SKIP_ACTION_NAMES.includes?(name)
              actions << {name: name, offset: i}
            end
            match_end = m.end(0)
            i = match_end ? i + match_end : i + 1
            next
          end
        end

        i += 1
      end

      # De-duplicate while preserving order (multiple matches can occur if
      # a closure-style action is followed by a method-style override).
      seen = Set(String).new
      actions.select do |entry|
        if seen.includes?(entry[:name])
          false
        else
          seen << entry[:name]
          true
        end
      end
    end

    private def parse_allowed_methods(body : String) : Hash(String, Array(String))
      mapping = {} of String => Array(String)
      header = body.match(/static\s+allowedMethods\s*=\s*\[/)
      return mapping unless header
      header_end = header.end(0)
      return mapping unless header_end

      depth = 1
      i = header_end
      while i < body.size && depth > 0
        c = body[i]
        case c
        when '['
          depth += 1
        when ']'
          depth -= 1
          break if depth == 0
        else
          # ignore
        end
        i += 1
      end
      return mapping if depth != 0
      inner = body[header_end...i]
      buffer = String::Builder.new
      entries = [] of String
      list_depth = 0
      inner.each_char do |ch|
        case ch
        when '['
          list_depth += 1
          buffer << ch
        when ']'
          list_depth -= 1 if list_depth > 0
          buffer << ch
        when ','
          if list_depth == 0
            entries << buffer.to_s
            buffer = String::Builder.new
          else
            buffer << ch
          end
        else
          buffer << ch
        end
      end
      tail = buffer.to_s.strip
      entries << tail unless tail.empty?

      entries.each do |entry|
        pair = entry.strip
        next if pair.empty?
        kv = pair.split(':', 2)
        next if kv.size < 2
        key = kv[0].strip.gsub(/['"]/, "")
        next if key.empty?
        value = kv[1].strip
        verbs = extract_method_list(value)
        mapping[key] = verbs unless verbs.empty?
      end

      mapping
    end

    private def extract_method_list(raw : String) : Array(String)
      cleaned = raw.gsub(/[\[\]]/, "")
      cleaned.split(',').compact_map do |token|
        verb = token.strip.gsub(/['"]/, "").upcase
        next unless HTTP_METHODS.includes?(verb)
        verb
      end
    end

    private def process_url_mappings(path : String, content : String)
      cleaned = strip_groovy_comments(content)

      # `<verb> '/path'(controller: 'foo', action: 'bar')`
      pattern = /\b(get|post|put|delete|patch|head|options)\s+(['"])([^'"]+)\2\s*\((.*?)\)/m
      cleaned.scan(pattern) do |match|
        verb = match[1].upcase
        url_pattern = match[3]
        line = line_for_offset(content, match.begin(0) || 0)
        @result << Endpoint.new(translate_pattern(url_pattern), verb,
          extract_path_params(url_pattern),
          Details.new(PathInfo.new(path, line)))
      end

      # `'/path'(controller: 'foo', action: 'bar', method: 'POST')`
      # — defaults to GET when no `method:` argument is supplied.
      simple_pattern = /(?:^|\n)\s*(['"])([^'"]+)\1\s*\(([^)]*?)\)/m
      cleaned.scan(simple_pattern) do |match|
        url_pattern = match[2]
        body_args = match[3]
        next unless body_args.includes?("controller:") || body_args.includes?("action:") || body_args.includes?("view:")
        verb = extract_method_arg(body_args) || "GET"
        line = line_for_offset(content, match.begin(0) || 0)
        @result << Endpoint.new(translate_pattern(url_pattern), verb,
          extract_path_params(url_pattern),
          Details.new(PathInfo.new(path, line)))
      end
    end

    private def extract_method_arg(body_args : String) : String?
      m = body_args.match(/method:\s*['"]([A-Za-z]+)['"]/)
      return unless m
      verb = m[1].upcase
      HTTP_METHODS.includes?(verb) ? verb : nil
    end

    private def translate_pattern(pattern : String) : String
      pattern.gsub(/\$([A-Za-z_][A-Za-z0-9_]*)\??/) { |_, m| ":#{m[1]}" }
    end

    private def extract_path_params(pattern : String) : Array(Param)
      params = [] of Param
      pattern.scan(/\$([A-Za-z_][A-Za-z0-9_]*)/) do |m|
        params << Param.new(m[1], "", "path")
      end
      params
    end

    private def extract_braced_block(text : String, start : Int32) : Tuple(String, Int32)?
      i = start
      while i < text.size && text[i] != '{'
        i += 1
      end
      return if i >= text.size

      body_start = i + 1
      depth = 1
      i += 1
      in_string = false
      string_quote = '\0'

      while i < text.size && depth > 0
        c = text[i]
        if in_string
          if c == '\\' && i + 1 < text.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '{'
          depth += 1
        when '}'
          depth -= 1
          break if depth == 0
        else
          # ignore
        end
        i += 1
      end

      return if depth != 0
      {text[body_start...i], body_start}
    end

    private def strip_groovy_comments(text : String) : String
      result = String::Builder.new
      i = 0
      chars = text.chars
      in_string = false
      string_quote = '\0'

      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\' && i + 1 < chars.size
            result << c
            result << chars[i + 1]
            i += 2
            next
          elsif c == string_quote
            in_string = false
          end
          result << c
          i += 1
          next
        end

        if c == '"' || c == '\''
          in_string = true
          string_quote = c
          result << c
          i += 1
          next
        end

        if i + 1 < chars.size && c == '/' && chars[i + 1] == '/'
          while i < chars.size && chars[i] != '\n'
            i += 1
          end
          next
        end

        if i + 1 < chars.size && c == '/' && chars[i + 1] == '*'
          i += 2
          while i + 1 < chars.size && !(chars[i] == '*' && chars[i + 1] == '/')
            result << '\n' if chars[i] == '\n'
            i += 1
          end
          i += 2 if i + 1 < chars.size
          next
        end

        result << c
        i += 1
      end

      result.to_s
    end

    private def line_for_offset(content : String, offset : Int32) : Int32
      return 1 if offset <= 0
      limit = offset > content.size ? content.size : offset
      count = 1
      i = 0
      while i < limit
        count += 1 if content[i] == '\n'
        i += 1
      end
      count
    end
  end
end
