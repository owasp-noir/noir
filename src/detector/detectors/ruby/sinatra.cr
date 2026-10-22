require "../../../models/detector"

module Detector::Ruby
  class Sinatra < Detector
    detector_for "ruby_sinatra",
      extensions: %w[.rb .ru .gemspec],
      basenames: %w[Gemfile Gemfile.lock]

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
  end
end
