require "../../../models/detector"

module Detector::Ruby
  class Grape < Detector
    detector_for "ruby_grape", extensions: %w[.rb .ru .gemspec], basenames: %w[Gemfile Gemfile.lock]

    # `"< Grape::API"` was a separate probe, but it contains `"Grape::API"`
    # so it can never match anything the shorter literal misses.
    SOURCE_MARKERS = Regex.union("Grape::API", /require\s+['"]grape['"]/)

    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("Gemfile")
        return true if gemfile_dependency?(file_contents, "grape")
      end

      if filename.ends_with?(".gemspec")
        return true if gemspec_dependency?(file_contents, "grape")
      end

      if filename.ends_with?(".rb")
        return true if content_matches?(file_contents, SOURCE_MARKERS)
      end

      false
    end
  end
end
