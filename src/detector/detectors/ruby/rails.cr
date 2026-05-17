require "../../../models/detector"

module Detector::Ruby
  class Rails < Detector
    # Modern Rails apps frequently skip the umbrella `gem "rails"` line
    # and pull the individual frameworks they actually use (railties +
    # actionpack + activerecord + ...). Treat `railties` as a unique
    # marker — it has no standalone use outside Rails — so those apps
    # are still detected.
    RAILS_GEMFILE_MARKERS = [
      "gem 'rails'",
      "gem \"rails\"",
      "gem 'railties'",
      "gem \"railties\"",
    ]

    # Multi-engine Rails projects (Spree, Solidus, larger Solidus
    # forks) push their Gemfile to just `gemspec` and declare
    # `s.add_dependency 'rails'` / `s.add_dependency 'railties'`
    # inside `<gem>.gemspec` files. Match both common DSL accessor
    # names (`s`, `spec`) and the runtime-dependency variant.
    RAILS_GEMSPEC_MARKERS = [
      "add_dependency 'rails'",
      "add_dependency \"rails\"",
      "add_dependency 'railties'",
      "add_dependency \"railties\"",
      "add_runtime_dependency 'rails'",
      "add_runtime_dependency \"rails\"",
      "add_runtime_dependency 'railties'",
      "add_runtime_dependency \"railties\"",
    ]

    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("Gemfile")
        return RAILS_GEMFILE_MARKERS.any? { |marker| file_contents.includes?(marker) }
      end

      if filename.ends_with?(".gemspec")
        return RAILS_GEMSPEC_MARKERS.any? { |marker| file_contents.includes?(marker) }
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
      @name = "ruby_rails"
    end
  end
end
