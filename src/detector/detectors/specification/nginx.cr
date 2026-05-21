require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Nginx < Detector
    # `.conf` is by far the most common extension for Nginx fragments;
    # a tilde-prefixed `nginx.conf` (no extension) is the canonical
    # main file in many distributions. Accept both.
    EXTENSIONS = {".conf"}

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless nginx_shape?(file_contents)

      CodeLocator.instance.push("nginx-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      return true if File.basename(filename) == "nginx.conf"
      EXTENSIONS.any? { |ext| filename.ends_with?(ext) }
    end

    def set_name
      @name = "nginx"
    end

    # Registers each Nginx config path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def nginx_shape?(content : String) : Bool
      # Distinguish from Apache `.conf` files (which use directive
      # blocks like `<Directory>`) and unrelated configs by requiring
      # at least one nginx-specific directive.
      content.includes?("location ") &&
        (content.includes?("server ") || content.includes?("server{") ||
          content.includes?("http {") || content.includes?("http{"))
    end
  end
end
