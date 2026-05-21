require "../../../models/detector"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class Vercel < Detector
    CONFIG_FILES = {"vercel.json", "now.json"}

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless valid_json?(file_contents)

      CodeLocator.instance.push("vercel-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      base = File.basename(filename)
      return false unless CONFIG_FILES.includes?(base)

      parent = File.dirname(filename)
      return true if parent == "." || parent.empty?

      absolute = File.expand_path(filename)
      @base_paths.any? do |base_path|
        File.join(File.expand_path(base_path), base) == absolute
      end
    end

    def set_name
      @name = "vercel"
    end

    # Registers Vercel config paths in `CodeLocator`.
    def idempotent? : Bool
      false
    end
  end
end
