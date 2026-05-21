require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class ApacheHttpd < Detector
    HTACCESS          = ".htaccess"
    APACHE_DIRECTIVES = ["<VirtualHost", "<Location", "<LocationMatch", "<Directory", "RewriteRule", "Alias ", "ProxyPass"]

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless apache_shape?(file_contents)

      CodeLocator.instance.push("apache-httpd-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      base = File.basename(filename)
      return true if base == HTACCESS
      filename.ends_with?(".conf") && !nginx_only?(filename)
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

    private def apache_shape?(content : String) : Bool
      APACHE_DIRECTIVES.any? { |d| content.includes?(d) }
    end
  end
end
