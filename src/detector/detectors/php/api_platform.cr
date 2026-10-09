require "../../../models/detector"

module Detector::Php
  # API Platform resources are class attributes (`#[ApiResource]`, `#[Get]`,
  # …), not routes, so neither the Symfony nor the Laravel analyzer sees them.
  class ApiPlatform < Detector
    detector_for "php_api_platform", extensions: %w[.php], basenames: %w[composer.json composer.lock]

    # Quoted so `api-platform/core-extra` style names don't match.
    PACKAGES = [%("api-platform/core"), %("api-platform/symfony"), %("api-platform/laravel"), %("api-platform/metadata")]

    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?("composer.json") || filename.ends_with?("composer.lock")
        return PACKAGES.any? { |package| file_contents.includes?(package) }
      end

      Noir::FileExtension.fold(filename).ends_with?(".php") && file_contents.matches?(/^\s*use\s+ApiPlatform\\Metadata\\/m)
    end
  end
end
