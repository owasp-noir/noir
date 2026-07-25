require "../../../models/detector"

module Detector::Ruby
  class Hanami < Detector
    detector_for "ruby_hanami",
      extensions: %w[.rb .ru .gemspec],
      basenames: %w[Gemfile Gemfile.lock]

    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("Gemfile")
        return gemfile_dependency?(file_contents, "hanami")
      end

      # Apps that vendor Hanami via a gemspec declare it as
      # `s.add_dependency 'hanami'`. The Hanami framework's own repo
      # deliberately won't match — its gemspec only carries
      # `spec.name = "hanami"`, and there are no app-level routes to
      # extract from the library source.
      if filename.ends_with?(".gemspec")
        return gemspec_dependency?(file_contents, "hanami")
      end

      false
    end
  end
end
