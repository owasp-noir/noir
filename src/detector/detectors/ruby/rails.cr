require "../../../models/detector"

module Detector::Ruby
  class Rails < Detector
    # Modern Rails apps frequently skip the umbrella `gem "rails"` line
    # and pull the individual frameworks they actually use (railties +
    # actionpack + activerecord + ...). Treat `railties` as a unique
    # marker — it has no standalone use outside Rails — so those apps
    # are still detected.
    RAILS_GEM_MARKERS = [
      "gem 'rails'",
      "gem \"rails\"",
      "gem 'railties'",
      "gem \"railties\"",
    ]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("Gemfile")

      RAILS_GEM_MARKERS.any? { |marker| file_contents.includes?(marker) }
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".rb") || filename.ends_with?(".ru") || File.basename(filename) == "Gemfile" || File.basename(filename) == "Gemfile.lock"
    end

    def set_name
      @name = "ruby_rails"
    end
  end
end
