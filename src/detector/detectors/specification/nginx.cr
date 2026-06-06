require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class Nginx < Detector
    # `.conf` is by far the most common extension for Nginx fragments;
    # `.tmpl`/`.template` files are common in docker-gen and deployment
    # repositories that render Nginx configs from templates.
    EXTENSIONS  = {".conf", ".tmpl", ".template"}
    LOCATION_RE = /^\s*location\s+(?:(?:=|~\*|~|\^~)\s+)?\S+/

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
      # Include fragments often contain only `location` blocks, so scan
      # executable directives instead of requiring a top-level server/http block.
      content.each_line do |raw|
        line = strip_template_actions(strip_comment(raw))
        return true if line.matches?(LOCATION_RE)
      end
      false
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
  end
end
