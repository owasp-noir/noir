require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class ApacheHttpd < Detector
    HTACCESS          = ".htaccess"
    APACHE_DIRECTIVES = [
      "<VirtualHost",
      "<Location",
      "<LocationMatch",
      "<Directory",
      "RewriteRule",
      "Alias",
      "ScriptAlias",
      "ProxyPass",
      "ProxyPassMatch",
      "Redirect",
      "RedirectMatch",
    ]
    APACHE_HINTS = APACHE_DIRECTIVES.flat_map do |directive|
      hint = directive.lchop("<")
      [hint, hint.downcase]
    end

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless apache_shape?(file_contents)

      CodeLocator.instance.push("apache-httpd-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      base = File.basename(filename)
      return true if base == HTACCESS
      apache_conf?(filename) && !nginx_only?(filename)
    end

    def set_name
      @name = "apache_httpd"
    end

    # Registers each Apache config path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    # Avoid claiming nginx-only fragments by name to prevent the
    # detector from registering files that obviously belong to the
    # other server. The content guard below is the authoritative
    # check; this is just a fast skip for paths that scream nginx.
    private def nginx_only?(filename : String) : Bool
      lower = filename.downcase
      lower.includes?("/nginx/") || lower.ends_with?("nginx.conf")
    end

    private def apache_conf?(filename : String) : Bool
      lower = filename.downcase
      lower.ends_with?(".conf") || lower.ends_with?(".conf.in") || lower.ends_with?(".conf.template")
    end

    private def apache_shape?(content : String) : Bool
      return false unless APACHE_HINTS.any? { |directive| content.includes?(directive) }

      content.each_line do |raw|
        line = raw.lstrip
        next if line.empty? || line.starts_with?('#')
        return true if APACHE_DIRECTIVES.any? { |directive| apache_directive?(line, directive) }
      end

      false
    end

    private def apache_directive?(line : String, directive : String) : Bool
      return false unless ascii_prefix?(line, directive)
      return true if directive.starts_with?('<')

      end_index = directive.size
      return true if end_index >= line.size

      line[end_index].whitespace?
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
  end
end
