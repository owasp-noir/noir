require "../../../models/detector"

module Detector::Ruby
  class Roda < Detector
    SOURCE_MARKERS = Regex.union(/<\s*Roda\b/, "Roda.route", /require\s+['"]roda['"]/)

    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("Gemfile")
        return true if gemfile_dependency?(file_contents, "roda")
      end

      if filename.ends_with?(".gemspec")
        return true if gemspec_dependency?(file_contents, "roda")
      end

      if filename.ends_with?(".rb")
        return true if content_matches?(file_contents, SOURCE_MARKERS)
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".rb") || filename.ends_with?(".ru") || filename.ends_with?(".gemspec") || File.basename(filename) == "Gemfile" || File.basename(filename) == "Gemfile.lock"
    end

    def set_name
      @name = "ruby_roda"
    end
  end
end
