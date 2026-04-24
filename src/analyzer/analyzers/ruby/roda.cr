require "../../engines/ruby_engine"

module Analyzer::Ruby
  class Roda < RubyEngine
    HTTP_METHOD_MATCHERS = ["get", "post", "put", "delete", "patch", "head", "options"]

    alias PrefixEntry = NamedTuple(depth: Int32, segments: Array(String), path_params: Array(String))

    def analyze
      parallel_file_scan do |path|
        next unless path.ends_with?(".rb")
        analyze_file(path)
      end

      @result
    end

    private def analyze_file(path : String)
      content = read_file_content(path)
      return unless content.includes?("Roda") || content.includes?("route do")

      in_route = false
      depth = 0
      prefix_stack = [] of PrefixEntry
      last_endpoint_index = -1

      content.each_line.with_index do |line, index|
        next unless line.valid_encoding?

        stripped_for_code = strip_comment(line)

        unless in_route
          if stripped_for_code =~ /\broute\s+(?:do\b|\{)/
            in_route = true
            depth = count_opens(stripped_for_code) - count_closes(stripped_for_code)
            prefix_stack.clear
            last_endpoint_index = -1
          end
          next
        end

        emitted = process_route_line(stripped_for_code, path, index, depth, prefix_stack)
        if emitted >= 0
          last_endpoint_index = emitted
        end

        extract_params_for_line(stripped_for_code, last_endpoint_index)

        opens = count_opens(stripped_for_code)
        closes = count_closes(stripped_for_code)
        depth += opens - closes

        while !prefix_stack.empty? && prefix_stack.last[:depth] > depth
          prefix_stack.pop
        end

        if depth <= 0
          in_route = false
          depth = 0
          prefix_stack.clear
          last_endpoint_index = -1
        end
      end
    end

    private def process_route_line(line : String, path : String, index : Int32,
                                   depth : Int32,
                                   prefix_stack : Array(PrefixEntry)) : Int32
      if m = line.match(/\br\.on\s+(.+?)\s*(?:do\b|\{)/)
        segments, path_params = parse_on_args(m[1])
        unless segments.empty? && path_params.empty?
          prefix_stack << {depth: depth + 1, segments: segments, path_params: path_params}
        end
        return -1
      end

      if line =~ /\br\.root\b/
        url = build_url(collect_segments(prefix_stack), nil, nil)
        url = "/" if url.empty?
        ep = build_endpoint(url, "GET", path, index)
        apply_path_params(ep, prefix_stack)
        @result << ep
        return @result.size - 1
      end

      HTTP_METHOD_MATCHERS.each do |verb|
        if m = line.match(/\br\.#{verb}\s+['"]([^'"]+)['"]/)
          url = build_url(collect_segments(prefix_stack), m[1], nil)
          ep = build_endpoint(url, verb.upcase, path, index)
          apply_path_params(ep, prefix_stack)
          @result << ep
          return @result.size - 1
        end

        if line =~ /\br\.#{verb}\b\s*(?:do\b|\{|\/|$)/
          url = build_url(collect_segments(prefix_stack), nil, nil)
          url = "/" if url.empty?
          ep = build_endpoint(url, verb.upcase, path, index)
          apply_path_params(ep, prefix_stack)
          @result << ep
          return @result.size - 1
        end
      end

      -1
    end

    private def extract_params_for_line(line : String, last_endpoint_index : Int32)
      return unless last_endpoint_index >= 0 && last_endpoint_index < @result.size

      endpoint = @result[last_endpoint_index]

      line.scan(/r\.params\[['"]([\w\-]+)['"]\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query")) if m.size > 1
      end
      line.scan(/r\.params\[:([\w]+)\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query")) if m.size > 1
      end
      line.scan(/(?<!r\.)\bparams\[['"]([\w\-]+)['"]\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query")) if m.size > 1
      end
      line.scan(/(?<!r\.)\bparams\[:([\w]+)\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query")) if m.size > 1
      end
      line.scan(/r\.cookies\[['"]([\w\-]+)['"]\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "cookie")) if m.size > 1
      end
      line.scan(/r\.cookies\[:([\w]+)\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "cookie")) if m.size > 1
      end
      line.scan(/request\.env\[['"]HTTP_([\w]+)['"]\]/) do |m|
        if m.size > 1
          header = m[1].split('_').map(&.capitalize).join('-')
          endpoint.push_param(Param.new(header, "", "header"))
        end
      end
    end

    private def collect_segments(stack : Array(PrefixEntry)) : Array(String)
      segs = [] of String
      stack.each { |entry| segs.concat(entry[:segments]) }
      segs
    end

    private def apply_path_params(endpoint : Endpoint, stack : Array(PrefixEntry))
      stack.each do |entry|
        entry[:path_params].each do |name|
          endpoint.push_param(Param.new(name, "", "path"))
        end
      end
    end

    private def build_url(prefix : Array(String), single : String?, extras : Array(String)?) : String
      parts = [] of String
      prefix.each { |s| append_segments(parts, s) }
      append_segments(parts, single) if single
      extras.try &.each { |s| append_segments(parts, s) }
      parts.empty? ? "/" : "/" + parts.join("/")
    end

    private def append_segments(parts : Array(String), raw : String)
      raw.split("/").each do |piece|
        trimmed = piece.strip
        parts << trimmed unless trimmed.empty?
      end
    end

    private def parse_on_args(args : String) : Tuple(Array(String), Array(String))
      segments = [] of String
      path_params = [] of String
      args.split(",").each do |part|
        token = part.strip
        next if token.empty?
        if token.starts_with?(':')
          name = token[1..].gsub(/[^\w]/, "")
          unless name.empty?
            segments << "{#{name}}"
            path_params << name
          end
        elsif m = token.match(/['"]([^'"]+)['"]/)
          segments << m[1]
        end
      end
      {segments, path_params}
    end

    private def strip_comment(line : String) : String
      idx = line.index('#')
      idx ? line[0, idx] : line
    end

    private def count_opens(line : String) : Int32
      line.scan(/\bdo\b|\{/).size
    end

    private def count_closes(line : String) : Int32
      line.scan(/\bend\b|\}/).size
    end

    private def build_endpoint(url : String, method : String, path : String, index : Int32) : Endpoint
      Endpoint.new(url, method, Details.new(PathInfo.new(path, index + 1)))
    end
  end
end
