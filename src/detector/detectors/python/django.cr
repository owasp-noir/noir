require "../../../models/detector"

module Detector::Python
  class Django < Detector
    detector_for "python_django", extensions: %w[.py]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      # Match framework imports while avoiding django_* packages
      has_from_import = file_contents.match(/(^|\n)\s*from\s+django\./)
      has_import = file_contents.match(/(^|\n)\s*import\s+django(\s|,|$)/)

      # Django REST Framework counts as Django. `rest_framework` is a hard
      # Django dependency — there is no non-Django project that imports it —
      # and the canonical DRF app module imports nothing from `django` at
      # all: a `urls.py` that only builds a router (`from
      # rest_framework.routers import DefaultRouter` … `urlpatterns =
      # router.urls`) beside a `views.py` of `rest_framework` ViewSets is a
      # complete, routable Django app with no `django.` import in sight.
      # Without this clause such an app detects as nothing, the Django
      # analyzer never runs over it, and every REST route it declares is
      # lost — the whole API surface of a project scanned app-by-app, and of
      # any monorepo whose Python service happens to be DRF-only.
      has_drf_import = file_contents.match(/(^|\n)\s*from\s+rest_framework[\s.]/) ||
                       file_contents.match(/(^|\n)\s*import\s+rest_framework(\s|,|\.|$)/)

      !!(has_from_import || has_import || has_drf_import)
    end
  end
end
