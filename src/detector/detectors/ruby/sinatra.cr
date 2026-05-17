require "../../../models/detector"

module Detector::Ruby
  class Sinatra < Detector
    GEMFILE_MARKERS = [
      "gem 'sinatra'",
      "gem \"sinatra\"",
    ]

    # Single-gem repos (e.g. Gollum) park their Gemfile at
    # `gemspec` and declare `s.add_dependency 'sinatra'` inside
    # the gemspec instead. Walk those files too.
    GEMSPEC_MARKERS = [
      "add_dependency 'sinatra'",
      "add_dependency \"sinatra\"",
      "add_runtime_dependency 'sinatra'",
      "add_runtime_dependency \"sinatra\"",
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
      @name = "ruby_sinatra"
    end
  end
end
