require "../../../models/detector"

module Detector::Ruby
  class Hanami < Detector
    GEMFILE_MARKERS = [
      "gem 'hanami'",
      "gem \"hanami\"",
    ]

    # Apps that vendor Hanami via a gemspec declare it as
    # `s.add_dependency 'hanami'`. The Hanami framework's own
    # repo deliberately won't match — its gemspec only carries
    # `spec.name = "hanami"`, and there are no app-level routes
    # to extract from the library source.
    GEMSPEC_MARKERS = [
      "add_dependency 'hanami'",
      "add_dependency \"hanami\"",
      "add_runtime_dependency 'hanami'",
      "add_runtime_dependency \"hanami\"",
    ]

    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("Gemfile")
        return GEMFILE_MARKERS.any? { |marker| file_contents.includes?(marker) }
      end

      if filename.ends_with?(".gemspec")
        return GEMSPEC_MARKERS.any? { |marker| file_contents.includes?(marker) }
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
      @name = "ruby_hanami"
    end
  end
end
