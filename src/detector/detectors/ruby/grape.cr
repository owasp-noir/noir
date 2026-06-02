require "../../../models/detector"

module Detector::Ruby
  class Grape < Detector
    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("Gemfile")
        return true if gemfile_dependency?(file_contents, "grape")
      end

      if filename.ends_with?(".gemspec")
        return true if gemspec_dependency?(file_contents, "grape")
      end

      if filename.ends_with?(".rb")
        return true if file_contents.includes?("Grape::API")
        return true if file_contents.includes?("< Grape::API")
        return true if file_contents.matches?(/require\s+['"]grape['"]/)
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".rb") || filename.ends_with?(".ru") || filename.ends_with?(".gemspec") || File.basename(filename) == "Gemfile" || File.basename(filename) == "Gemfile.lock"
    end

    def set_name
      @name = "ruby_grape"
    end
  end
end
