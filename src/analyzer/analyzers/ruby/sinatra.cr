require "../../engines/ruby_engine"

module Analyzer::Ruby
  class Sinatra < RubyEngine
    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      parallel_file_scan do |path|
        next unless path.ends_with?(".rb") || path.ends_with?(".ru")
        # Minitest (`*_test.rb`) and RSpec (`*_spec.rb`) suites both
        # register Sinatra routes from inline test apps purely to
        # exercise the framework. Sinatra's own repo accounts for
        # ~145 such routes; production code never adopts either
        # filename convention so the suffix check is safe.
        next if RubyEngine.ruby_test_path?(path)
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          lines = file.each_line.to_a
          last_endpoint = Endpoint.new("", "")
          prefix_stack = [] of NamedTuple(depth: Int32, path: String)
          depth = 0
          lines.each_with_index do |line, index|
            next unless line.valid_encoding?
            # Skip Ruby comment lines — `sinatra-contrib/lib/sinatra/
            # namespace.rb` and similar library sources keep DSL
            # examples (`#     get '/dashboard' do`) inside RDoc
            # comments. They look identical to real route
            # registrations to the line-based matcher.
            stripped = Noir::RubyCalleeExtractor.strip_comment(line, preserve_strings: true).strip
            next if stripped.empty? || stripped.starts_with?('#')

            if ns = stripped.match(/^namespace\s*\(?\s*['"]([^'"]+)['"]\s*\)?\s+do\b/)
              prefix_stack << {depth: depth + 1, path: ns[1]}
            end

            endpoint = line_to_endpoint(line)
            unless endpoint.method.empty?
              endpoint.url = sinatra_prefixed_path(prefix_stack, endpoint.url)
              details = Details.new(PathInfo.new(path, index + 1))
              endpoint.details = details
              attach_route_callees(endpoint, lines, index, path) if include_callee
              @result << endpoint
              last_endpoint = endpoint
            end

            param = line_to_param(line)
            unless param.name.empty?
              unless last_endpoint.method.empty?
                last_endpoint.push_param(param)
              end
            end

            depth += sinatra_block_opens(stripped) - sinatra_block_closes(stripped)
            while !prefix_stack.empty? && prefix_stack.last[:depth] > depth
              prefix_stack.pop
            end
          end
        end
      end

      @result
    end

    private def attach_route_callees(endpoint : Endpoint, lines : Array(String), index : Int32, path : String)
      if block = extract_ruby_do_block(lines, index)
        body, body_start_line = block
        callees = Noir::RubyCalleeExtractor.callees_for_body(body, path, body_start_line)
        attach_ruby_callees(endpoint, callees)
      end
    end

    def line_to_param(content : String) : Param
      if content.includes? "param["
        param = content.split("param[")[1].split("]")[0].gsub("\"", "").gsub("'", "").gsub(":", "")
        return Param.new(param, "", "query")
      end

      if content.includes? "params["
        param = content.split("params[")[1].split("]")[0].gsub("\"", "").gsub("'", "").gsub(":", "")
        return Param.new(param, "", "query")
      end

      if content.includes? "request.env["
        param = content.split("request.env[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "header")
      end

      if content.includes? "headers["
        param = content.split("headers[")[1].split("]")[0].gsub("\"", "").gsub("'", "").gsub(":", "")
        return Param.new(param, "", "header")
      end

      if content.includes? "cookies["
        param = content.split("cookies[")[1].split("]")[0].gsub("\"", "").gsub("'", "").gsub(":", "")
        return Param.new(param, "", "cookie")
      end

      Param.new("", "", "")
    end

    private def sinatra_prefixed_path(prefix_stack : Array(NamedTuple(depth: Int32, path: String)), path : String) : String
      parts = [] of String
      prefix_stack.each { |entry| append_sinatra_path(parts, entry[:path]) }
      append_sinatra_path(parts, path)
      parts.empty? ? "/" : "/#{parts.join("/")}"
    end

    private def append_sinatra_path(parts : Array(String), raw : String)
      raw.split("/").each do |piece|
        trimmed = piece.strip
        parts << trimmed unless trimmed.empty?
      end
    end

    private def sinatra_block_opens(line : String) : Int32
      line.scan(/\bdo\b|\{/).size
    end

    private def sinatra_block_closes(line : String) : Int32
      line.scan(/\bend\b|\}/).size
    end
  end
end
