require "../../../models/detector"

module Detector::Ruby
  class Rails < Detector
    detector_for "ruby_rails", extensions: %w[.rb .ru .gemspec], basenames: %w[Gemfile Gemfile.lock]

    # Modern Rails apps frequently skip the umbrella `rails` dependency and
    # pull the individual frameworks they actually use (railties +
    # actionpack + activerecord + ...). Treat `railties` as a unique marker
    # — it has no standalone use outside Rails — so those apps are still
    # detected. Multi-engine projects (Spree, Solidus) push their Gemfile to
    # `gemspec` and declare the dependency inside `<gem>.gemspec` instead;
    # the tolerant matchers accept the `s.add_dependency('rails', ...)`
    # parenthesized call form those gemspecs commonly use.
    RAILS_GEMS = ["rails", "railties"]

    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("Gemfile")
        return RAILS_GEMS.any? { |gem_name| gemfile_dependency?(file_contents, gem_name) }
      end

      if filename.ends_with?(".gemspec")
        return RAILS_GEMS.any? { |gem_name| gemspec_dependency?(file_contents, gem_name) }
      end

      false
    end
  end
end
