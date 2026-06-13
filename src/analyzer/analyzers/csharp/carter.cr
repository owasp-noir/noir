require "../../../models/analyzer"
require "./common"

module Analyzer::CSharp
  # Extracts endpoints from Carter (https://github.com/CarterCommunity/Carter)
  # modules — classes implementing `ICarterModule` that register
  # minimal-API routes inside `AddRoutes(IEndpointRouteBuilder)`.
  #
  # The extraction is scoped to each `AddRoutes` body so that
  # MapGroup prefixes don't leak across modules, and so that files
  # owned by the `cs_aspnet_core_mvc` analyzer (which skips
  # `ICarterModule` files) are not double-counted with a stale tech
  # tag.
  class Carter < Analyzer
    include Common

    MAP_METHODS = %w[Get Post Put Delete Patch Head Options]

    def analyze
      include_callee = callees_needed?

      get_files_by_extension(".cs").each do |file|
        next unless File.exists?(file)
        next if Common.csharp_test_path?(file)

        content = read_file_content(file)
        next unless content.includes?("ICarterModule")

        lines = content.lines
        each_add_routes_block(lines) do |block_lines, block_start_index|
          group_prefixes = extract_map_group_prefixes(block_lines)
          analyze_add_routes_block(block_lines, block_start_index, file, lines, group_prefixes, include_callee)
        end
      end

      @result
    end

    private def each_add_routes_block(lines : Array(String), &)
      masked_lines = Noir::CSharpLexer.new(lines.join('\n')).masked_lines
      i = 0
      while i < lines.size
        line = lines[i]
        if add_routes_signature?(line)
          _, end_index = build_signature(lines, masked_lines, i)
          body_start = end_index
          block_lines, body_end = collect_method_body_lines(lines, body_start)
          yield block_lines, body_start
          i = body_end
        end
        i += 1
      end
    end

    private def add_routes_signature?(line : String) : Bool
      return false unless line.includes?("AddRoutes")
      line.includes?("public") || line.includes?("void")
    end

    private def collect_method_body_lines(lines : Array(String), start_index : Int32) : Tuple(Array(String), Int32)
      collected = [] of String
      brace = 0
      started = false
      index = start_index

      while index < lines.size
        line = lines[index]
        brace += line.count('{') - line.count('}')
        if !started && line.includes?("{")
          started = true
          collected << line
          if brace <= 0 && line.includes?("}")
            return {collected, index}
          end
          index += 1
          next
        end

        if started
          collected << line
          if brace <= 0
            return {collected, index}
          end
        end

        index += 1
      end

      {collected, index}
    end

    private def analyze_add_routes_block(block_lines : Array(String), block_start_index : Int32, file : String, file_lines : Array(String), group_prefixes : Hash(String, String), include_callee : Bool)
      map_regex = /(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?Map(Get|Post|Put|Delete|Patch|Head|Options)\s*\(\s*"([^"]+)"/m
      chained_group_map_regex = /MapGroup\s*\(\s*"([^"]+)"\s*\)\s*\.Map(Get|Post|Put|Delete|Patch|Head|Options)\s*\(\s*"([^"]+)"/m
      map_methods_block_regex = /(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?MapMethods\s*\(\s*"([^"]+)"\s*,\s*([\s\S]+?)=>/m
      chained_group_map_methods_regex = /MapGroup\s*\(\s*"([^"]+)"\s*\)\s*\.MapMethods\s*\(\s*"([^"]+)"\s*,\s*([\s\S]+?)=>/m

      block_lines.each_with_index do |line, local_index|
        absolute_index = block_start_index + local_index

        if route_builder_line?(line)
          block = extract_map_block(block_lines, local_index)
          if chained_match = chained_group_map_regex.match(block)
            http_method = chained_match[2].upcase
            route = join_route_parts(chained_match[1], chained_match[3])
          elsif match = map_regex.match(block)
            receiver = match[1]?
            http_method = match[2].upcase
            route = apply_group_prefix(match[3], receiver, group_prefixes)
          else
            route = nil
            http_method = nil
          end

          if route && http_method
            extra_params = extract_params_from_block(block)
            extra_params.concat(extract_bind_params_from_file(block, file_lines))
            endpoint = build_endpoint_from_route(route, http_method, file, absolute_index + 1, extra_params)
            if endpoint
              attach_csharp_callees(endpoint, block, file, absolute_index + 1, include_callee)
              @result << endpoint
            end
          end
        end

        if line.includes?("MapMethods")
          block = extract_map_block(block_lines, local_index)
          route = nil
          methods = [] of String

          if chained_match = chained_group_map_methods_regex.match(block)
            route = join_route_parts(chained_match[1], chained_match[2])
            methods_section = chained_match[3]
            methods = methods_section.scan(/"([A-Za-z]+)"/).map(&.[1]?.to_s.upcase).reject(&.empty?).uniq!
          elsif match = block.match(/(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?MapMethods\s*\(\s*"([^"]+)"\s*,\s*new[^{]*\{([^}]*)\}/m)
            receiver = match[1]?
            route = apply_group_prefix(match[2], receiver, group_prefixes)
            methods = match[3].split(",").map(&.gsub(/["\s]/, "").upcase).reject(&.empty?).uniq!
          elsif match = map_methods_block_regex.match(block)
            receiver = match[1]?
            route = apply_group_prefix(match[2], receiver, group_prefixes)
            methods_section = match[3]
            methods = methods_section.scan(/"([A-Za-z]+)"/).map(&.[1]?.to_s.upcase).reject(&.empty?).uniq!
          end

          if route && methods.size > 0
            extra_params = extract_params_from_block(block)
            extra_params.concat(extract_bind_params_from_file(block, file_lines))
            methods.each do |method|
              endpoint = build_endpoint_from_route(route, method, file, absolute_index + 1, extra_params)
              if endpoint
                attach_csharp_callees(endpoint, block, file, absolute_index + 1, include_callee)
                @result << endpoint
              end
            end
          end
        end
      end
    end

    private def route_builder_line?(line : String) : Bool
      MAP_METHODS.any? { |verb| line.includes?("Map#{verb}") }
    end

    private def extract_map_group_prefixes(block_lines : Array(String)) : Hash(String, String)
      prefixes = Hash(String, String).new
      group_assignment_regex = /(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*\.MapGroup\s*\(\s*"([^"]+)"\s*\)/

      block_lines.each_with_index do |line, idx|
        # The assignment can only match a line that mentions `MapGroup`. Skipping
        # the rest keeps the unbounded identifier captures from backtracking across
        # a long token run (e.g. a multi-kilobyte route literal), which is O(n²).
        next unless line.includes?("MapGroup")

        # The `var x =` head may sit on the previous line
        # (`var g =\n  app.MapGroup("/x")`), so match over a two-line window. The
        # window is bounded, so it can't reintroduce the cross-block backtracking
        # the per-line guard removed. A single-line assignment matched again from
        # the next line's window just rewrites the same key with the same value.
        window = idx > 0 ? "#{block_lines[idx - 1]}\n#{line}" : line
        window.scan(group_assignment_regex) do |match|
          variable = match[1]
          parent = match[2]
          prefix = match[3]
          parent_prefix = prefixes[parent]? || ""
          prefixes[variable] = join_route_parts(parent_prefix, prefix)
        end
      end

      prefixes
    end

    private def apply_group_prefix(route : String, receiver : String?, group_prefixes : Hash(String, String)) : String
      return route unless receiver
      prefix = group_prefixes[receiver]?
      return route unless prefix
      join_route_parts(prefix, route)
    end

    private def join_route_parts(*parts : String) : String
      clean_parts = parts.compact_map do |part|
        clean = part.strip.gsub(/^\//, "").gsub(/\/$/, "")
        clean.empty? ? nil : clean
      end
      return "/" if clean_parts.empty?
      "/" + clean_parts.join("/")
    end

    private def extract_map_block(lines : Array(String), start_index : Int32) : String
      io = String::Builder.new
      paren_depth = 0
      brace_depth = 0
      i = start_index

      while i < lines.size
        line = lines[i]
        paren_depth += line.count('(') - line.count(')')
        brace_depth += line.count('{') - line.count('}')
        io << line
        io << '\n'

        if paren_depth <= 0 && brace_depth <= 0 && line.includes?(";")
          break
        end

        i += 1
      end

      io.to_s
    end

    private def extract_params_from_block(block : String) : Array(Param)
      params = [] of Param
      query_regex = /Request\.Query\["([^"]+)"\]/
      header_regex = /Request\.Headers\["([^"]+)"\]/
      cookie_regex = /Request\.Cookies\["([^"]+)"\]/
      form_regex = /Request\.Form\["([^"]+)"\]/
      json_property_regex = /GetProperty\s*\(\s*"([^"]+)"\s*\)/

      block.scan(query_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "query") if key && !key.empty?
      end
      block.scan(header_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "header") if key && !key.empty?
      end
      block.scan(cookie_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "cookie") if key && !key.empty?
      end
      block.scan(form_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "form") if key && !key.empty?
      end
      block.scan(json_property_regex) do |match|
        key = match[1]? || match[0]
        params << Param.new(key, "", "json") if key && !key.empty?
      end

      params.uniq(&.name)
    end

    private def extract_bind_params_from_file(block : String, lines : Array(String)) : Array(Param)
      return [] of Param unless block.includes?("Bind(") || block.includes?("BindAsync(")

      params = [] of Param
      masked_lines = Noir::CSharpLexer.new(lines.join('\n')).masked_lines
      lines.each_with_index do |line, index|
        next unless line.includes?("Bind(") || line.includes?("BindAsync(")
        next unless line.includes?("public") || line.includes?("private") || line.includes?("protected") || line.includes?("internal") || line.includes?("static")

        _, end_idx = build_signature(lines, masked_lines, index)
        body = extract_method_block(lines, masked_lines, end_idx)
        params.concat(extract_params_from_block(body))
      end

      params.uniq(&.name)
    end

    private def build_endpoint_from_route(raw_route : String, http_method : String, file : String, line : Int32, extra_params : Array(Param) = [] of Param) : Endpoint?
      return if raw_route.empty?

      route = normalize_route(raw_route)
      params = build_path_params(route)
      extra_params.each do |param|
        params << param unless params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      end
      route = prune_optional_placeholders(route, params)

      details = Details.new(PathInfo.new(file, line))
      endpoint = Endpoint.new(route, http_method, details)
      params.each { |param| endpoint.params << param }
      endpoint
    end

    private def normalize_route(route : String) : String
      normalized = route.strip
      normalized = normalized.gsub(/^\//, "").gsub(/\/+/, "/")
      normalized = "/" + normalized unless normalized.starts_with?("/")
      normalized = "/" if normalized == "//" || normalized == "/"
      normalized
    end

    private def build_path_params(route : String) : Array(Param)
      extract_route_placeholders(route).map do |name|
        Param.new(name, "", "path")
      end
    end

    private def prune_optional_placeholders(route : String, parameters : Array(Param)) : String
      param_names = parameters.map(&.name)
      result = route.dup

      placeholder_regex = /\{([^}]+)\}/
      route.scan(placeholder_regex) do |match|
        raw = match[1]? || match[0]
        next unless raw

        optional = raw.ends_with?("?")
        name = raw.split(":").first
        name = name.gsub(/\?$/, "")

        if optional && !param_names.includes?(name)
          result = result.gsub("/{#{raw}}", "")
          result = result.gsub("{#{raw}}/", "")
          result = result.gsub("{#{raw}}", "")
        elsif optional
          cleaned = raw.gsub("?", "")
          result = result.gsub("{#{raw}}", "{#{cleaned}}")
        end
      end

      result
    end

    private def extract_route_placeholders(route : String) : Array(String)
      keys = [] of String
      placeholder_regex = /\{([^}]+)\}/

      route.scan(placeholder_regex) do |match|
        raw = match[1]? || match[0]
        next unless raw
        cleaned = raw.split(":").first
        cleaned = cleaned.gsub(/\?$/, "")
        cleaned = cleaned.lstrip("*")
        keys << cleaned
      end

      keys.uniq
    end
  end
end
