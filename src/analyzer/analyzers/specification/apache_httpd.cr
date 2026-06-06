require "../../../models/analyzer"

module Analyzer::Specification
  class ApacheHttpd < Analyzer
    METHOD_ANY = "ANY"

    REDIRECT_STATUSES = Set{"permanent", "temp", "temporary", "seeother", "gone"}
    STATIC_EXTENSIONS = Set{".css", ".js", ".gz", ".br", ".ico", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".woff", ".woff2", ".ttf", ".eot", ".map"}

    def analyze
      spec_files = CodeLocator.instance.all("apache-httpd-spec")
      return @result unless spec_files.is_a?(Array(String))

      spec_files.each do |path|
        next unless File.exists?(path)

        content = read_file_content(path)
        begin
          process_content(content, path)
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def process_content(content : String, path : String)
      hosts = [] of String
      line_no = 0

      content.each_line do |raw|
        line_no += 1
        line = strip_comment(raw).strip
        next if line.empty?

        if block_open?(line, "VirtualHost")
          hosts = [] of String
        elsif block_close?(line, "VirtualHost")
          hosts = [] of String
        elsif directive?(line, "ServerName")
          args = directive_args(line, "ServerName")
          hosts << args[0] if args.size > 0
        elsif directive?(line, "ServerAlias")
          directive_args(line, "ServerAlias").each { |alias_host| hosts << alias_host }
        elsif location = block_arg(line, "Location")
          emit_endpoint(location, "prefix", hosts, "location", path, line_no)
        elsif location = block_arg(line, "LocationMatch")
          emit_endpoint(location, "regex", hosts, "locationmatch", path, line_no)
        elsif directive?(line, "Alias")
          emit_first_path_arg(line, "Alias", "alias", "alias", hosts, path, line_no)
        elsif directive?(line, "ScriptAlias")
          emit_first_path_arg(line, "ScriptAlias", "script-alias", "scriptalias", hosts, path, line_no)
        elsif directive?(line, "ProxyPass")
          emit_proxy_pass(line, "ProxyPass", "proxy", "proxypass", hosts, path, line_no)
        elsif directive?(line, "ProxyPassMatch")
          emit_proxy_pass(line, "ProxyPassMatch", "proxy-regex", "proxypassmatch", hosts, path, line_no)
        elsif directive?(line, "Redirect")
          emit_redirect(line, "Redirect", "redirect", "redirect", hosts, path, line_no)
        elsif directive?(line, "RedirectMatch")
          emit_redirect(line, "RedirectMatch", "redirect-regex", "redirectmatch", hosts, path, line_no)
        elsif directive?(line, "RewriteRule")
          emit_rewrite(line, hosts, path, line_no)
        end
      end
    end

    private def emit_first_path_arg(line : String, directive : String, path_type : String, origin : String, hosts : Array(String), source_path : String, line_no : Int32)
      args = directive_args(line, directive)
      return if args.size < 2

      path_value = args[0]
      return unless path_like?(path_value)

      emit_endpoint(path_value, path_type, hosts, origin, source_path, line_no)
    end

    private def emit_proxy_pass(line : String, directive : String, path_type : String, origin : String, hosts : Array(String), source_path : String, line_no : Int32)
      args = directive_args(line, directive)
      return if args.size < 2

      path_value = args[0]
      target = args[1]
      return unless path_like?(path_value)
      return if target == "!"

      emit_endpoint(path_value, path_type, hosts, origin, source_path, line_no, target)
    end

    private def emit_redirect(line : String, directive : String, path_type : String, origin : String, hosts : Array(String), source_path : String, line_no : Int32)
      args = directive_args(line, directive)
      return if args.empty?

      path_index = redirect_status?(args[0]) ? 1 : 0
      return if path_index >= args.size

      path_value = args[path_index]
      target = args[path_index + 1]?
      return unless path_like?(path_value)

      emit_endpoint(path_value, path_type, hosts, origin, source_path, line_no, target)
    end

    private def emit_rewrite(line : String, hosts : Array(String), source_path : String, line_no : Int32)
      args = directive_args(line, "RewriteRule")
      return if args.size < 2

      pattern = args[0]
      target = args[1]
      return if skip_rewrite?(pattern, target)

      emit_endpoint(pattern, "rewrite-source", hosts, "rewrite", source_path, line_no, target)
    end

    private def directive_args(line : String, directive : String) : Array(String)
      offset = directive_offset(line, directive)
      return [] of String unless offset

      split_args(line[(offset + directive.size)..])
    end

    private def split_args(value : String) : Array(String)
      args = [] of String
      current = String::Builder.new
      quote = nil.as(Char?)
      escaped = false

      value.each_char do |char|
        if escaped
          current << char
          escaped = false
          next
        end

        if quote
          case char
          when '\\'
            escaped = true
          when quote
            quote = nil
          else
            current << char
          end
          next
        end

        case char
        when '"', '\''
          quote = char
        when .whitespace?
          unless current.empty?
            args << current.to_s
            current = String::Builder.new
          end
        else
          current << char
        end
      end

      args << current.to_s unless current.empty?
      args
    end

    private def block_arg(line : String, directive : String) : String?
      return unless block_open?(line, directive)

      offset = directive_offset(line, directive)
      return unless offset

      tail = line[(offset + directive.size)..].strip
      close = tail.rindex('>')
      return unless close

      strip_quotes(tail[0...close].strip)
    end

    private def block_open?(line : String, directive : String) : Bool
      offset = directive_offset(line, directive)
      return false unless offset
      return false if offset == 1 && line.size > 1 && line[1] == '/'

      line.starts_with?('<')
    end

    private def block_close?(line : String, directive : String) : Bool
      return false unless line.starts_with?("</")
      ascii_prefix?(line, "</#{directive}")
    end

    private def directive?(line : String, directive : String) : Bool
      !!directive_offset(line, directive)
    end

    private def directive_offset(line : String, directive : String) : Int32?
      offset = line.starts_with?('<') ? 1 : 0
      return unless ascii_prefix?(line[offset..], directive)

      end_index = offset + directive.size
      return offset if end_index >= line.size

      char = line[end_index]
      return offset if char.whitespace? || char == '>'
      nil
    end

    private def ascii_prefix?(value : String, prefix : String) : Bool
      return false if value.size < prefix.size

      prefix.each_byte.each_with_index do |byte, idx|
        return false unless ascii_downcase(value.byte_at(idx)) == ascii_downcase(byte)
      end

      true
    end

    private def ascii_downcase(byte : UInt8) : UInt8
      if byte >= 65 && byte <= 90
        byte + 32
      else
        byte
      end
    end

    private def redirect_status?(value : String) : Bool
      lower = value.downcase
      REDIRECT_STATUSES.includes?(lower) || lower.matches?(/^\d{3}$/)
    end

    private def path_like?(value : String) : Bool
      return false if value.empty?
      return true if value.starts_with?('/') || value.starts_with?("^/") || value.starts_with?("./") || value.starts_with?("../")
      return true if value.starts_with?("^\\.") || value.starts_with?("\\.")
      false
    end

    private def skip_rewrite?(pattern : String, target : String) : Bool
      return true if target == "-"
      return true if static_asset_rewrite?(pattern, target)
      false
    end

    private def static_asset_rewrite?(pattern : String, target : String) : Bool
      STATIC_EXTENSIONS.any? do |ext|
        pattern.includes?(ext) && target.includes?(ext)
      end
    end

    private def strip_quotes(value : String) : String
      v = value.strip
      return v unless v.size >= 2
      if (v.starts_with?('"') && v.ends_with?('"')) || (v.starts_with?('\'') && v.ends_with?('\''))
        return v[1...-1]
      end
      v
    end

    private def strip_comment(line : String) : String
      quote = nil.as(Char?)
      escaped = false

      line.each_char_with_index do |char, idx|
        if escaped
          escaped = false
          next
        end

        if quote
          case char
          when '\\'
            escaped = true
          when quote
            quote = nil
          end
          next
        end

        case char
        when '"', '\''
          quote = char
        when '#'
          return line[0...idx]
        end
      end

      line
    end

    private def emit_endpoint(path : String, path_type : String, hosts : Array(String), origin : String, source_path : String, line : Int32, target : String? = nil)
      return if path.empty?

      detail = Details.new(PathInfo.new(source_path, line))
      hosts = [""] if hosts.empty?
      hosts.each do |host|
        endpoint = Endpoint.new(path, METHOD_ANY, detail)
        endpoint.add_tag(Tag.new("apache-path-type", path_type, "apache_httpd_analyzer"))
        endpoint.add_tag(Tag.new("apache-host", host, "apache_httpd_analyzer")) unless host.empty?
        endpoint.add_tag(Tag.new("apache-source", origin, "apache_httpd_analyzer"))
        endpoint.add_tag(Tag.new("apache-rewrite-target", target, "apache_httpd_analyzer")) if target && !target.empty?
        @result << endpoint
      end
    end
  end
end
