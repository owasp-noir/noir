require "../../../models/analyzer"
require "../../../miniparsers/haskell_callee_extractor"
require "set"

module Analyzer::Haskell
  class Yesod < Analyzer
    HTTP_METHODS = %w[GET POST PUT DELETE PATCH OPTIONS HEAD]
    alias HandlerBody = Noir::HaskellCalleeExtractor::FunctionBody
    # A handler name can occur in more than one file; keep all bodies and only
    # attach callees when the name resolves unambiguously (mirrors scotty.cr),
    # rather than last-write-wins overwriting across files.
    alias HandlerKey = Tuple(String, String)
    alias HandlerBodies = Hash(HandlerKey, Array(HandlerBody))

    def analyze
      processed_route_files = Set(String).new
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      handler_bodies = include_callee ? build_handler_bodies : HandlerBodies.new

      all_files.each do |path|
        next if File.directory?(path)

        if route_file?(path)
          expanded_path = File.expand_path(path)
          next if processed_route_files.includes?(expanded_path)

          process_route_content(expanded_path, read_file_content(path), include_callee, handler_bodies)
          processed_route_files << expanded_path
          next
        end

        next unless haskell_source?(path)

        content = read_file_content(path)
        extract_inline_route_blocks(content).each do |block|
          process_route_content(path, block, include_callee, handler_bodies)
        end

        extract_external_route_paths(content).each do |relative_path|
          referenced_path = File.expand_path(relative_path, File.dirname(path))
          next unless File.exists?(referenced_path)
          next if File.directory?(referenced_path)
          next if processed_route_files.includes?(referenced_path)

          process_route_content(referenced_path, read_file_content(referenced_path), include_callee, handler_bodies)
          processed_route_files << referenced_path
        end
      end

      @result
    end

    private def haskell_source?(path : String) : Bool
      path.ends_with?(".hs") || path.ends_with?(".lhs")
    end

    private def route_file?(path : String) : Bool
      return true if path.ends_with?(".yesodroutes")

      File.basename(path) == "routes" && File.dirname(path).ends_with?("/config")
    end

    private def build_handler_bodies : HandlerBodies
      handlers = HandlerBodies.new

      all_files.each do |path|
        next if File.directory?(path)
        next unless haskell_source?(path)

        Noir::HaskellCalleeExtractor.function_bodies(read_file_content(path), path).each do |body|
          key = handler_key(configured_base_for(path), body[:name])
          (handlers[key] ||= [] of HandlerBody) << body
        end
      end

      handlers
    end

    private def handler_key(base_path : String, name : String) : HandlerKey
      {base_path, name}
    end

    private def extract_inline_route_blocks(content : String) : Array(String)
      blocks = [] of String

      content.scan(/\[(?:parseRoutes|parseRoutesNoCheck)\|([\s\S]*?)\|\]/) do |match|
        next if match.size < 2
        blocks << match[1]
      end

      blocks
    end

    private def extract_external_route_paths(content : String) : Array(String)
      paths = [] of String

      content.scan(/parseRoutesFile(?:NoCheck)?\s*\(?\s*["']([^"']+)["']/) do |match|
        next if match.size < 2
        paths << match[1]
      end

      paths.uniq
    end

    private def process_route_content(source_path : String,
                                      content : String,
                                      include_callee : Bool,
                                      handler_bodies : HandlerBodies)
      scope_stack = [{indent: -1, raw_segments: [] of String}]

      logical_route_lines(content).each do |entry|
        stripped_line = strip_route_comment(entry[:text]).strip
        next if stripped_line.empty?

        tokens = split_route_tokens(stripped_line)
        next if tokens.size < 2
        route_name = tokens[1]

        indent = entry[:indent]
        while scope_stack.size > 1 && indent <= scope_stack.last[:indent]
          scope_stack.pop
        end

        raw_segments = extract_raw_segments(tokens[0])
        if tokens.last.ends_with?(':')
          scope_stack << {
            indent:       indent,
            raw_segments: scope_stack.last[:raw_segments] + raw_segments,
          }
          next
        end

        methods = extract_methods(tokens)
        next if methods.empty?
        methodless_route = methodless_route?(tokens)

        url, params = build_url_and_params(scope_stack.last[:raw_segments] + raw_segments)
        details = Details.new(PathInfo.new(source_path, entry[:line]))

        methods.each do |method|
          endpoint_params = params.map { |param| Param.new(param.name, param.value, param.param_type) }
          endpoint = Endpoint.new(url, method, endpoint_params, details)
          attach_handler_callees(endpoint, method, route_name, methodless_route, source_path, handler_bodies) if include_callee
          @result << endpoint
        end
      end
    end

    private def attach_handler_callees(endpoint : Endpoint,
                                       method : String,
                                       route_name : String,
                                       methodless_route : Bool,
                                       source_path : String,
                                       handler_bodies : HandlerBodies)
      handler_name = handler_name_for(method, route_name, methodless_route)
      bodies = handler_bodies[handler_key(configured_base_for(source_path), handler_name)]?
      # Only attach when the name is unambiguous; a name defined in multiple
      # files under the same base would otherwise pull callees from the wrong
      # file's body.
      return unless bodies && bodies.size == 1
      handler_body = bodies.first

      callees = Noir::HaskellCalleeExtractor.callees_for_body(
        handler_body[:body],
        handler_body[:path],
        handler_body[:start_line]
      )
      Noir::HaskellCalleeExtractor.attach_to(endpoint, callees)
    end

    private def handler_name_for(method : String, route_name : String, methodless_route : Bool) : String
      return "handle#{route_name}" if methodless_route

      method.downcase + route_name
    end

    private def logical_route_lines(content : String) : Array(NamedTuple(text: String, line: Int32, indent: Int32))
      lines = [] of NamedTuple(text: String, line: Int32, indent: Int32)
      buffer = ""
      buffer_line = 1

      content.each_line.with_index(1) do |raw_line, line_number|
        line = raw_line.sub(/\n\z/, "").sub(/\r\z/, "")

        if buffer.empty?
          buffer = line
          buffer_line = line_number
        else
          buffer += line
        end

        trimmed = line.rstrip
        if trimmed.ends_with?("\\")
          buffer = buffer.rstrip
          buffer = buffer[0...-1] if buffer.ends_with?("\\")
          next
        end

        lines << {
          text:   buffer,
          line:   buffer_line,
          indent: leading_spaces(buffer),
        }
        buffer = ""
      end

      unless buffer.empty?
        lines << {
          text:   buffer,
          line:   buffer_line,
          indent: leading_spaces(buffer),
        }
      end

      lines
    end

    private def leading_spaces(line : String) : Int32
      count = 0
      line.each_char do |char|
        break unless char == ' '
        count += 1
      end
      count
    end

    private def strip_route_comment(line : String) : String
      chars = line.chars
      brace_depth = 0
      index = 0

      while index < chars.size
        char = chars[index]

        if char == '{'
          brace_depth += 1
        elsif char == '}' && brace_depth > 0
          brace_depth -= 1
        elsif brace_depth == 0 && char == '-' && index + 1 < chars.size && chars[index + 1] == '-'
          return chars[0...index].join
        end

        index += 1
      end

      line
    end

    private def split_route_tokens(line : String) : Array(String)
      tokens = [] of String
      current = String::Builder.new
      has_content = false
      brace_depth = 0

      line.each_char do |char|
        if char == '{'
          brace_depth += 1
          current << char
          has_content = true
        elsif char == '}'
          brace_depth -= 1 if brace_depth > 0
          current << char
          has_content = true
        elsif char.whitespace? && brace_depth == 0
          # Flush the pending token. Guard on `has_content` so a `String::Builder`
          # is only stringified once — consecutive whitespace (common in
          # alignment-padded routes files) would otherwise call `to_s` twice on
          # the same builder and raise.
          if has_content
            tokens << current.to_s
            current = String::Builder.new
            has_content = false
          end
        else
          current << char
          has_content = true
        end
      end

      tokens << current.to_s if has_content
      tokens
    end

    private def extract_methods(tokens : Array(String)) : Array(String)
      return [] of String if tokens.size < 2

      rest = tokens[2..]? || [] of String
      non_attrs = rest.reject(&.starts_with?("!"))
      explicit_methods = non_attrs.select { |token| HTTP_METHODS.includes?(token) }

      return explicit_methods unless explicit_methods.empty?
      return [] of String if looks_like_subsite_dispatch?(non_attrs)
      return HTTP_METHODS.dup if non_attrs.empty?

      [] of String
    end

    private def methodless_route?(tokens : Array(String)) : Bool
      rest = tokens[2..]? || [] of String
      non_attrs = rest.reject(&.starts_with?("!"))
      non_attrs.empty?
    end

    # Yesod subsite declarations use two non-method tokens after the route
    # constructor: the subsite type and the getter function.
    private def looks_like_subsite_dispatch?(tokens : Array(String)) : Bool
      tokens.size == 2 && tokens.none? { |token| HTTP_METHODS.includes?(token) }
    end

    private def extract_raw_segments(pattern : String) : Array(String)
      normalized = pattern
      while normalized.starts_with?("!") || normalized.starts_with?("/")
        normalized = normalized[1..]
      end

      return [] of String if normalized.empty?

      normalized.split('/').reject(&.empty?).map { |segment| strip_overlap_markers(segment) }
    end

    private def build_url_and_params(raw_segments : Array(String)) : Tuple(String, Array(Param))
      rendered_segments = [] of String
      params = [] of Param
      name_counts = Hash(String, Int32).new(0)

      raw_segments.each do |raw_segment|
        segment = raw_segment

        if segment.starts_with?("#")
          type_name = segment[1..]
          param_name = next_param_name(type_name, name_counts)
          rendered_segments << ":#{param_name}"
          params << Param.new(param_name, clean_type_name(type_name), "path")
        elsif segment.starts_with?("*") || segment.starts_with?("+")
          type_name = segment[1..]
          param_name = next_param_name(type_name, name_counts)
          rendered_segments << "*#{param_name}"
          params << Param.new(param_name, clean_type_name(type_name), "path")
        else
          rendered_segments << segment
        end
      end

      url = rendered_segments.empty? ? "/" : "/#{rendered_segments.join("/")}"
      {url, params}
    end

    private def strip_overlap_markers(segment : String) : String
      segment.gsub("!", "")
    end

    private def next_param_name(type_name : String, name_counts : Hash(String, Int32)) : String
      base_name = sanitize_param_name(type_name)
      current_count = name_counts[base_name]? || 0
      current_count += 1
      name_counts[base_name] = current_count

      return base_name if current_count == 1
      "#{base_name}_#{current_count}"
    end

    private def clean_type_name(type_name : String) : String
      cleaned = type_name.strip
      cleaned = cleaned[1...-1] if cleaned.starts_with?("{") && cleaned.ends_with?("}")
      cleaned
    end

    private def sanitize_param_name(type_name : String) : String
      base_name = clean_type_name(type_name)
        .gsub(/[\[\](){}]/, " ")
        .gsub(/([a-z0-9])([A-Z])/) { "#{$1}_#{$2}" }
        .gsub(/[^A-Za-z0-9]+/, "_")
        .downcase
        .gsub(/^_+|_+$/, "")
        .gsub(/_+/, "_")

      base_name.empty? ? "param" : base_name
    end
  end
end
