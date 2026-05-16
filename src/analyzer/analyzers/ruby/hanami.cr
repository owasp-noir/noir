require "../../engines/ruby_engine"

module Analyzer::Ruby
  class Hanami < RubyEngine
    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      framework_roots = discover_framework_roots("config/routes.rb")
      framework_roots = [@base_path] if framework_roots.empty?

      framework_roots.each do |framework_root|
        path = "#{framework_root}/config/routes.rb"
        next unless File.exists?(path)

        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          file.each_line.with_index do |line, index|
            details = Details.new(PathInfo.new(path, index + 1))
            endpoint = line_to_endpoint(line, details)
            if endpoint.method != ""
              # Extract action path from route
              action_path = extract_action_path(line, framework_root)
              if action_path != ""
                # Scan action file for parameters
                scan_action_file(endpoint, action_path, include_callee)
              end

              @result << endpoint
            end
          end
        end
      end

      @result
    end

    def extract_action_path(content : String, framework_root : String = @base_path) : String
      # Extract action from to: parameter, e.g., to: "books.index" -> app/actions/books/index.rb
      content.scan(/to:\s*['"](.+?)['"]/) do |match|
        if match.size > 1
          action = match[1]
          # Convert "books.index" to "app/actions/books/index.rb"
          return "#{framework_root}/app/actions/#{action.gsub(".", "/")}.rb"
        end
      end
      ""
    end

    def scan_action_file(endpoint : Endpoint, action_path : String, include_callee : Bool = false)
      return unless File.exists?(action_path)

      lines = [] of String
      File.open(action_path, "r", encoding: "utf-8", invalid: :skip) do |file|
        lines = file.each_line.to_a
      end

      scan_action_params(endpoint, lines)
      attach_handle_callees(endpoint, action_path, lines) if include_callee
    end

    private def scan_action_params(endpoint : Endpoint, lines : Array(String))
      in_params_block = false

      lines.each do |line|
        # Detect params block
        if line.strip == "params do"
          in_params_block = true
          next
        elsif line.strip == "end" && in_params_block
          in_params_block = false
          next
        end

        # Extract params from params block
        # Matches required(:name) or optional(:name) - validation methods like
        # .filled(), .value(), .maybe() are chained after and don't affect extraction
        if in_params_block
          # Match required(:name) or optional(:name) with any validation method
          line.scan(/(?:required|optional)\(:([\w]+)\)/) do |match|
            if match.size > 1
              param_name = match[1]
              # Determine if it's JSON or form based on content type
              param_type = "json"
              endpoint.push_param(Param.new(param_name, "", param_type))
            end
          end
        end

        # Extract query parameters from request.params[:name]
        line.scan(/request\.params\[:([\w]+)\]/) do |match|
          if match.size > 1
            param_name = match[1]
            endpoint.push_param(Param.new(param_name, "", "query"))
          end
        end

        # Extract query parameters from request.params["name"]
        line.scan(/request\.params\[['"](\w+)['"]\]/) do |match|
          if match.size > 1
            param_name = match[1]
            endpoint.push_param(Param.new(param_name, "", "query"))
          end
        end

        # Extract query parameters from params[:name] (without request prefix)
        # Use word boundary to avoid matching params inside method names or identifiers
        # Avoid matching inside params do blocks
        unless in_params_block
          line.scan(/(?<!\.)\bparams\[:([\w]+)\]/) do |match|
            if match.size > 1
              param_name = match[1]
              endpoint.push_param(Param.new(param_name, "", "query"))
            end
          end
        end

        # Extract query parameters from params["name"] (without request prefix)
        # Use word boundary to avoid matching params inside method names or identifiers
        # Avoid matching inside params do blocks
        unless in_params_block
          line.scan(/(?<!\.)\bparams\[['"](\w+)['"]\]/) do |match|
            if match.size > 1
              param_name = match[1]
              endpoint.push_param(Param.new(param_name, "", "query"))
            end
          end
        end

        # Extract header parameters from request.headers['name'] or request.headers["name"]
        line.scan(/request\.headers\[['"](.+?)['"]\]/) do |match|
          if match.size > 1
            param_name = match[1]
            endpoint.push_param(Param.new(param_name, "", "header"))
          end
        end

        # Extract cookie parameters from request.cookies['name'] or request.cookies["name"]
        line.scan(/request\.cookies\[['"](.+?)['"]\]/) do |match|
          if match.size > 1
            param_name = match[1]
            endpoint.push_param(Param.new(param_name, "", "cookie"))
          end
        end

        # Extract environment headers from request.env['HTTP_*']
        line.scan(/request\.env\[['"]HTTP_(.+?)['"]\]/) do |match|
          if match.size > 1
            # Convert HTTP_USER_AGENT to User-Agent format
            header_name = match[1].split('_').map(&.capitalize).join('-')
            endpoint.push_param(Param.new(header_name, "", "header"))
          end
        end
      end
    end

    private def attach_handle_callees(endpoint : Endpoint, action_path : String, lines : Array(String))
      if block = extract_handle_body(lines)
        body, body_start_line = block
        callees = Noir::RubyCalleeExtractor.callees_for_body(body, action_path, body_start_line)
        attach_ruby_callees(endpoint, callees)
      end
    end

    private def extract_handle_body(lines : Array(String)) : Tuple(String, Int32)?
      index = 0

      while index < lines.size
        stripped = Noir::RubyCalleeExtractor.strip_comment(lines[index]).strip
        if match = stripped.match(/^(?:private\s+|protected\s+|public\s+)?def\s+(?:self\.)?handle\b/)
          inline_body, closed_on_def_line = inline_def_body(stripped, match[0])
          body_lines = [] of String
          body_start_line = inline_body ? index + 1 : index + 2
          body_lines << inline_body if inline_body

          unless closed_on_def_line
            depth = 1
            index += 1

            while index < lines.size
              raw_body_line = lines[index]
              body_line = Noir::RubyCalleeExtractor.strip_comment(raw_body_line).strip

              if closes_ruby_block?(body_line)
                depth -= 1
                break if depth == 0
                body_lines << raw_body_line
                index += 1
                next
              end

              body_lines << raw_body_line
              depth += ruby_do_block_open_delta(body_line)
              index += 1
            end
          end

          return {body_lines.join("\n"), body_start_line}
        end

        index += 1
      end
    end

    private def inline_def_body(line : String, match_text : String) : Tuple(String?, Bool)
      return {nil, false} if match_text.size >= line.size

      tail = line[match_text.size, line.size - match_text.size].strip
      tail = tail.sub(/^\([^)]*\)\s*/, "")
      if tail.starts_with?("=")
        body = tail[1, tail.size - 1].strip
        return {body.empty? ? nil : body, true}
      end

      return {nil, false} unless tail.starts_with?(";")

      tail = tail[1, tail.size - 1].strip
      if match = tail.match(/^(.*?)(?:;\s*)?end\b/)
        body = match[1].strip
        return {body.empty? ? nil : body, true}
      end

      {tail.empty? ? nil : tail, false}
    end

    private def closes_ruby_block?(line : String) : Bool
      !!line.match(/^end\b/)
    end
  end
end
