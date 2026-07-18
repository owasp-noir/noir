require "../../../models/detector"

module Detector::Python
  class DjangoNinja < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

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

    def applicable?(filename : String) : Bool
      filename.ends_with?(".py")
    end

    def set_name
      @name = "python_django_ninja"
    end
  end
end
