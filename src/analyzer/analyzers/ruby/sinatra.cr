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
          active_route_endpoints = [] of Endpoint
          active_route_depth = nil.as(Int32?)
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

            if ns = stripped.match(/^namespace\s*\(?\s*['"]([^'"]+)['"]\s*\)?\s*(?:do\b|\{)/)
              prefix_stack << {depth: depth + 1, path: ns[1]}
            end

            route_endpoints = line_to_endpoints(stripped)
            unless route_endpoints.empty?
              route_endpoints.each do |endpoint|
                endpoint.url = sinatra_prefixed_path(prefix_stack, endpoint.url)
                details = Details.new(PathInfo.new(path, index + 1))
                endpoint.details = details
                attach_route_callees(endpoint, lines, index, path) if include_callee
                @result << endpoint
              end

              if sinatra_block_opens(stripped) > sinatra_block_closes(stripped)
                active_route_endpoints = route_endpoints
                active_route_depth = depth + 1
              else
                active_route_endpoints = [] of Endpoint
                active_route_depth = nil
              end
            end

            line_to_params(stripped).each do |param|
              target_endpoints = if route_endpoints.empty?
                                   if (route_depth = active_route_depth) && !active_route_endpoints.empty? && depth >= route_depth
                                     active_route_endpoints
                                   else
                                     [] of Endpoint
                                   end
                                 else
                                   route_endpoints
                                 end

              target_endpoints.each do |endpoint|
                endpoint.push_param(param)
              end
            end

            depth += sinatra_block_opens(stripped) - sinatra_block_closes(stripped)
            while !prefix_stack.empty? && prefix_stack.last[:depth] > depth
              prefix_stack.pop
            end
            if (route_depth = active_route_depth) && depth < route_depth
              active_route_endpoints = [] of Endpoint
              active_route_depth = nil
            end
          end
        end
      end

      @result
    end

    private def line_to_endpoints(content : String) : Array(Endpoint)
      route_endpoints = route_call_to_endpoints(content)
      return route_endpoints unless route_endpoints.empty?

      endpoint = line_to_endpoint(content)
      endpoint.method.empty? ? ([] of Endpoint) : [endpoint]
    end

    private def route_call_to_endpoints(content : String) : Array(Endpoint)
      leading = content.lstrip
      return [] of Endpoint unless leading.starts_with?("route")
      return [] of Endpoint if leading.size > 5 && (leading[5].alphanumeric? || leading[5] == '_')

      path = nil.as(String?)
      verb_source = leading
      leading.scan(/['"]([^'"]+)['"]/) do |m|
        candidate = m[1]
        if candidate.starts_with?("/")
          path = candidate
          verb_source = leading[0, m.begin(0) || 0]
          break
        end
      end
      return [] of Endpoint unless route_path = path

      verbs = [] of String
      verb_source.scan(/:(get|post|put|patch|delete|head|options)\b/i) do |m|
        verbs << m[1].upcase
      end
      verb_source.scan(/['"](GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)['"]/i) do |m|
        verbs << m[1].upcase
      end
      verb_source.scan(/%[iw][\[\(]([^\]\)]*)[\]\)]/) do |m|
        m[1].split(/\s+/).each do |verb|
          normalized = verb.strip.lchop(":").upcase
          verbs << normalized if HTTP_VERBS.includes?(normalized.downcase)
        end
      end

      verbs.uniq.map { |verb| Endpoint.new(route_path, verb) }
    end

    private def attach_route_callees(endpoint : Endpoint, lines : Array(String), index : Int32, path : String)
      if block = extract_ruby_do_block(lines, index)
        body, body_start_line = block
        callees = Noir::RubyCalleeExtractor.callees_for_body(body, path, body_start_line)
        attach_ruby_callees(endpoint, callees)
      end
    end

    def line_to_param(content : String) : Param
      line_to_params(content).first? || Param.new("", "", "")
    end

    private def line_to_params(content : String) : Array(Param)
      params = [] of Param

      content.scan(/param\[\s*(?::(\w+)|['"]([^'"]+)['"])\s*\]/) do |m|
        name = (m[1]? || m[2]?).to_s.strip
        params << Param.new(name, "", "query") unless name.empty?
      end

      content.scan(/params\[\s*(?::(\w+)|['"]([^'"]+)['"])\s*\]/) do |m|
        name = (m[1]? || m[2]?).to_s.strip
        params << Param.new(name, "", "query") unless name.empty?
      end

      content.scan(/params\.fetch\s*\(\s*(?::(\w+)|['"]([^'"]+)['"])/) do |m|
        name = (m[1]? || m[2]?).to_s.strip
        params << Param.new(name, "", "query") unless name.empty?
      end

      content.scan(/request\.env\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        name = m[1].strip
        params << Param.new(name, "", "header") unless name.empty?
      end

      content.scan(/headers\[\s*(?::(\w+)|['"]([^'"]+)['"])\s*\]/) do |m|
        name = (m[1]? || m[2]?).to_s.strip
        params << Param.new(name, "", "header") unless name.empty?
      end

      content.scan(/cookies\[\s*(?::(\w+)|['"]([^'"]+)['"])\s*\]/) do |m|
        name = (m[1]? || m[2]?).to_s.strip
        params << Param.new(name, "", "cookie") unless name.empty?
      end

      params
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
