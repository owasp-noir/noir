require "../../../models/detector"

module Detector::Python
  class DjangoNinja < Detector
    detector_for "python_django_ninja", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")
      # Necessary condition for every pattern below, which all spell
      # `ninja` literally: a memchr scan is far cheaper than the anchored
      # import regexes, and a file without the word cannot match them.
      return false unless file_contents.includes?("ninja")

      # django-ninja is imported as the `ninja` package. Match
      # `from ninja import ...` and `from ninja.<submodule> import ...`
      # (e.g. `ninja.security`, `ninja.router`) plus a bare
      # `import ninja`. A word boundary keeps `ninja_extra`,
      # `ninja_syntax`, etc. out. A bare `import ninja` also matches the
      # unrelated Ninja build-file generator, but a false positive only
      # yields zero endpoints, so the cheap broad match is acceptable.
      has_from_import = file_contents.match(/(^|\n)\s*from\s+ninja(\.\w|\s+import)/)
      has_import = file_contents.match(/(^|\n)\s*import\s+ninja(\s|,|\.|$)/)

      !!(has_from_import || has_import)
    end
  end
end
