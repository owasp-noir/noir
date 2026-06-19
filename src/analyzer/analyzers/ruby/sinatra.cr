require "../../engines/ruby_engine"

module Analyzer::Ruby
  class Sinatra < RubyEngine
    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      parallel_file_scan do |path|
        next unless path.ends_with?(".rb") || path.ends_with?(".ru")
        next if ruby_non_production_path?(path)
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

            line_delta = sinatra_depth_delta(line)

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

              if line_delta > 0
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

            depth += line_delta
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

    # `params[:splat]` (the `*` wildcard matches) and `params[:captures]`
    # (regex route captures) are Sinatra's framework bindings for the
    # route pattern itself, not user-supplied query fields — the `*`/regex
    # segment is already modeled in the URL.
    SINATRA_RESERVED_PARAMS = Set{"splat", "captures"}

    private def line_to_params(content : String) : Array(Param)
      params = [] of Param

      content.scan(/param\[\s*(?::(\w+)|['"]([^'"]+)['"])\s*\]/) do |m|
        name = (m[1]? || m[2]?).to_s.strip
        params << Param.new(name, "", "query") unless name.empty? || SINATRA_RESERVED_PARAMS.includes?(name)
      end

      content.scan(/params\[\s*(?::(\w+)|['"]([^'"]+)['"])\s*\]/) do |m|
        name = (m[1]? || m[2]?).to_s.strip
        params << Param.new(name, "", "query") unless name.empty? || SINATRA_RESERVED_PARAMS.includes?(name)
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

    # Net change in block nesting contributed by a single line. Unlike a
    # naive `{`/`do` open vs `}`/`end` close tally, this:
    #   * blanks string interiors first, so `#{...}` interpolation and
    #     any DSL keyword that merely appears inside a string literal
    #     never skew the count;
    #   * credits statement-position keyword blocks (`if`, `unless`,
    #     `case`, `begin`, `while`, `until`, `for`, `class`, `module`,
    #     `def`) with the `+1` their matching `end` will later subtract.
    # The previous open/close split counted every `end` as a close while
    # ignoring the `if`/`case`/… that opened it. A single multi-line `if`
    # inside a route body therefore popped the surrounding `namespace`
    # prefix early — gollum dropped `/gollum` from ~17 real routes
    # (`/gollum/last_commit_info` surfaced as `/last_commit_info`). Modifier
    # forms (`forbid unless x`, `return if y`) sit mid-line, never at a
    # statement boundary, so they are correctly left uncounted.
    private def sinatra_depth_delta(line : String) : Int32
      structure = Noir::RubyCalleeExtractor.strip_comment(line, preserve_strings: false)
      delta = structure.count('{') - structure.count('}')
      structure.scan(/\bdo\b/) { delta += 1 }
      structure.scan(/(?:^|;)\s*(?:if|unless|case|begin|while|until|for|class|module|def)\b/) { delta += 1 }
      structure.scan(/\bend\b/) { delta -= 1 }
      delta
    end
  end
end
