require "../../../models/detector"

module Detector::Ruby
  # Padrino is a full-stack framework built directly on top of Sinatra —
  # every Padrino app also carries Sinatra's route-registration DSL, so the
  # Sinatra detector legitimately fires on Padrino projects too (see
  # `NoirTechs::Catalog::Ruby::PADRINO`'s `:supersedes`). This detector needs
  # its own, more specific positive signal so `ruby_padrino` is additive
  # rather than a re-detection of `ruby_sinatra` under another name.
  class Padrino < Detector
    detector_for "ruby_padrino", extensions: %w[.rb .ru .gemspec], basenames: %w[Gemfile Gemfile.lock]

    # `Padrino::Application` is the base class every mountable sub-app
    # inherits from, `Padrino.mount` is the `config/apps.rb` mounting call,
    # and `require 'padrino-core'` / `require 'padrino'` cover apps that
    # pull the framework in without ever subclassing `Padrino::Application`
    # directly (e.g. a single-file app built on `Padrino::Routing`).
    SOURCE_MARKERS = Regex.union(
      "Padrino::Application",
      "Padrino.mount",
      /require\s+['"]padrino-core['"]/,
      /require\s+['"]padrino['"]/
    )

    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("Gemfile")
        return true if gemfile_dependency?(file_contents, "padrino")
        return true if gemfile_dependency?(file_contents, "padrino-core")
      end

      if filename.ends_with?(".gemspec")
        return true if gemspec_dependency?(file_contents, "padrino")
        return true if gemspec_dependency?(file_contents, "padrino-core")
      end

      if filename.ends_with?(".rb")
        return true if content_matches?(file_contents, SOURCE_MARKERS)
      end

      false
    end
  end
end
