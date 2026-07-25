require "../../../models/detector"

module Detector::Ruby
  class Roda < Detector
    detector_for "ruby_roda", extensions: %w[.rb .ru .gemspec], basenames: %w[Gemfile Gemfile.lock]

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
  end
end
