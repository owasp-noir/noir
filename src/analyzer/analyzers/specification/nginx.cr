require "../../../models/analyzer"

module Analyzer::Specification
  class Nginx < Analyzer
    METHOD_ANY = "ANY"

    LOCATION_RE     = /^location\s+(?:(=|~\*|~|\^~)\s+)?(\S+)/
    SERVER_NAME_RE  = /^server_name\s+([^;]+);?/
    LISTEN_TLS_RE   = /\bssl\b|\bhttp2\b/
    LISTEN_RE       = /^listen\b/
    METHOD_BLOCK_RE = /^if\s*\(\s*\$request_method\s*=\s*([A-Z]+)\s*\)/

    def analyze
      spec_files = CodeLocator.instance.all("nginx-spec")
      return @result unless spec_files.is_a?(Array(String))

      spec_files.each do |path|
        next unless File.exists?(path)

        details = Details.new(PathInfo.new(path))
        content = read_file_content(path)
        begin
          process_content(content, details)
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private record Frame, kind : String, value : String, line : Int32

    private def process_content(content : String, details : Details)
      stack = [] of Frame
      server_names = [] of String
      server_tls = false
      server_depth = 0

      content.each_line.with_index do |raw, idx|
        line = strip_template_actions(strip_comment(raw)).strip
        next if line.empty?

        # Pre-handle a trailing `}` so we pop the closing frame
        # before processing the rest of the line's directives.
        balanced = line
        while balanced.starts_with?("}")
          pop_frame(stack)
          if stack.empty?
            server_names = [] of String
            server_tls = false
            server_depth = 0
          end
          balanced = balanced[1..].strip
          break if balanced.empty?
        end
        next if balanced.empty?

        if balanced.matches?(/^server\s*\{/)
          stack << Frame.new("server", "", idx + 1)
          server_names = [] of String
          server_tls = false
          server_depth = stack.size
        elsif m = SERVER_NAME_RE.match(balanced)
          m[1].split(/\s+/).reject(&.empty?).each { |n| server_names << n }
        elsif balanced.matches?(LISTEN_RE)
          server_tls = true if balanced.matches?(LISTEN_TLS_RE)
        elsif m = LOCATION_RE.match(balanced)
          modifier = m[1]? || ""
          raw_location = m[2]
          location = normalize_location_path(raw_location)
          unless location.empty? || internal_location?(raw_location) || internal_location?(location)
            stack << Frame.new("location", location, idx + 1)
            emit_location(details, location, modifier, METHOD_ANY, server_names, server_tls, idx + 1)
          end
        elsif m = METHOD_BLOCK_RE.match(balanced)
          method = m[1].upcase
          if loc = current_location(stack)
            emit_location(details, loc.value, "", method, server_names, server_tls, idx + 1)
          end
          stack << Frame.new("block", "", idx + 1) if balanced.includes?('{')
        elsif balanced.matches?(/\{\s*$/)
          stack << Frame.new("block", "", idx + 1)
        end

        # Handle inline closing braces on this same line (after directive).
        balanced.each_char { |ch| pop_frame(stack) if ch == '}' }
      end
    end

    private def pop_frame(stack : Array(Frame))
      stack.pop unless stack.empty?
    end

    private def current_location(stack : Array(Frame)) : Frame?
      stack.reverse_each { |f| return f if f.kind == "location" }
    end

    private def strip_comment(line : String) : String
      previous = '\0'
      line.each_char_with_index do |ch, idx|
        if ch == '#' && (idx == 0 || previous.whitespace? || previous.in?(';', '{', '}'))
          return line[0...idx]
        end
        previous = ch
      end
      line
    end

    private def strip_template_actions(line : String) : String
      line.gsub(/\{\{.*?\}\}/, "")
    end

    private def normalize_location_path(path : String) : String
      path.gsub(/[{};]\z/, "")
    end

    private def internal_location?(path : String) : Bool
      path.starts_with?("@") || path.includes?("{{") || path.includes?("}}")
    end

    private def emit_location(details : Details, path : String, modifier : String, method : String, hosts : Array(String), tls : Bool, line : Int32)
      return if path.empty?

      path_type = case modifier
                  when "="  then "exact"
                  when "~"  then "regex"
                  when "~*" then "regex-i"
                  when "^~" then "prefix-stop"
                  else           "prefix"
                  end

      detail = Details.new(PathInfo.new(details.code_paths.first.path, line))
      hosts = [""] if hosts.empty?
      hosts.each do |host|
        endpoint = Endpoint.new(path, method, detail)
        endpoint.add_tag(Tag.new("nginx-path-type", path_type, "nginx_analyzer"))
        endpoint.add_tag(Tag.new("nginx-host", host, "nginx_analyzer")) unless host.empty?
        endpoint.protocol = "https" if tls
        @result << endpoint
      end
    end
  end
end
