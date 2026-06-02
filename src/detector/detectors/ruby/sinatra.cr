require "../../../models/detector"

module Detector::Ruby
  class Sinatra < Detector
    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("Gemfile")
        return gemfile_dependency?(file_contents, "sinatra")
      end

      # Single-gem repos (e.g. Gollum, geminabox) park their Gemfile at
      # `gemspec` and declare the dependency inside the gemspec instead.
      if filename.ends_with?(".gemspec")
        return gemspec_dependency?(file_contents, "sinatra")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".rb") ||
        filename.ends_with?(".ru") ||
        filename.ends_with?(".gemspec") ||
        File.basename(filename) == "Gemfile" ||
        File.basename(filename) == "Gemfile.lock"
    end

    def set_name
      @name = "ruby_sinatra"
    end
  end
end
