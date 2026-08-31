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

    # Rails APIs that cannot appear in a project that is not Rails, so a
    # single `.rb` or `.ru` file is enough to place the whole tree.
    #
    # The dependency declaration is the better marker when it is there, but
    # it is only there when the scan reaches the manifest. Point noir at a
    # Rails app's `config/` directory, at an engine whose gemspec does not
    # name the framework, or at a service inside a monorepo scanned
    # app-by-app, and there is no Gemfile in the walk — the app detects as
    # nothing, the Rails analyzer never runs, and every route the app
    # declares is lost. That is the same gap the Django detector closes for
    # DRF-only apps, and it is worth closing here because the file the
    # analyzer actually reads, `config/routes.rb`, is itself proof:
    # `.routes.draw` is the Rails routing DSL and belongs to no other
    # framework.
    RAILS_CODE_MARKERS = [
      # config/routes.rb, in both the modern and the pre-3.0 spelling
      # (`AppName::Application.routes.draw do`).
      /(^|\W)[A-Za-z_:][\w:]*\.routes\.draw\b/,
      # config.ru and initializers: `run Rails.application`.
      /(^|\W)Rails\.application\b/,
      # config/application.rb: `class Application < Rails::Application`.
      /(^|\W)Rails::Application\b/,
      # config/application.rb, top of file.
      /(^|\s)require\s+["']rails\/all["']/,
    ]

    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("Gemfile")
        return RAILS_GEMS.any? { |gem_name| gemfile_dependency?(file_contents, gem_name) }
      end

      if filename.ends_with?(".gemspec")
        return RAILS_GEMS.any? { |gem_name| gemspec_dependency?(file_contents, gem_name) }
      end

      if filename.ends_with?(".rb") || filename.ends_with?(".ru")
        return RAILS_CODE_MARKERS.any? { |marker| file_contents.matches?(marker) }
      end

      false
    end
  end
end
