require "../../../models/analyzer"

module Analyzer::Specification
  class ApacheHttpd < Analyzer
    METHOD_ANY = "ANY"

    LOCATION_OPEN_RE       = /^<Location\s+([^>]+)>/i
    LOCATION_MATCH_OPEN_RE = /^<LocationMatch\s+([^>]+)>/i
    DIRECTORY_OPEN_RE      = /^<Directory\s+([^>]+)>/i
    VHOST_OPEN_RE          = /^<VirtualHost\s+([^>]*)>/i
    VHOST_CLOSE_RE         = /^<\/VirtualHost>/i
    SERVER_NAME_RE         = /^ServerName\s+(\S+)/i
    SERVER_ALIAS_RE        = /^ServerAlias\s+(.+)/i
    ALIAS_RE               = /^Alias\s+(\S+)\s+(\S+)/i
    REWRITE_RE             = /^RewriteRule\s+(\S+)\s+(\S+)/i

    def analyze
      spec_files = CodeLocator.instance.all("apache-httpd-spec")
      return @result unless spec_files.is_a?(Array(String))

      spec_files.each do |path|
        next unless File.exists?(path)

        details = Details.new(PathInfo.new(path))
        content = read_file_content(path)
        begin
          process_content(content, path, details)
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def process_content(content : String, path : String, details : Details)
      hosts = [] of String
      in_vhost = false

      content.lines.each_with_index do |raw, idx|
        line = strip_comment(raw).strip
        next if line.empty?
        line_no = idx + 1

        if VHOST_OPEN_RE.match(line)
          in_vhost = true
          hosts = [] of String
        elsif VHOST_CLOSE_RE.match(line)
          in_vhost = false
          hosts = [] of String
        elsif m = SERVER_NAME_RE.match(line)
          hosts << m[1]
        elsif m = SERVER_ALIAS_RE.match(line)
          m[1].split(/\s+/).reject(&.empty?).each { |alias_host| hosts << alias_host }
        elsif m = LOCATION_OPEN_RE.match(line)
          location = strip_quotes(m[1].strip)
          emit_endpoint(location, "prefix", hosts, "location", path, line_no)
        elsif m = LOCATION_MATCH_OPEN_RE.match(line)
          location = strip_quotes(m[1].strip)
          emit_endpoint(location, "regex", hosts, "locationmatch", path, line_no)
        elsif m = ALIAS_RE.match(line)
          path_value = strip_quotes(m[1])
          emit_endpoint(path_value, "alias", hosts, "alias", path, line_no)
        elsif m = REWRITE_RE.match(line)
          pattern = strip_quotes(m[1])
          target = strip_quotes(m[2])
          emit_endpoint(pattern, "rewrite-source", hosts, "rewrite", path, line_no, target)
        end
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
      idx = line.index('#')
      idx.nil? ? line : line[0...idx]
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
