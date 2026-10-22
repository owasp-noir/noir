require "../../../models/detector"

module Detector::Php
  # Livewire / Volt: the composer package, or a class importing the
  # component base. Laravel's own Blade components extend
  # `Illuminate\View\Component`, so the namespace is what tells them apart.
  class Livewire < Detector
    detector_for "php_livewire", extensions: %w[.php], basenames: %w[composer.json]

    COMPOSER_RE = /"livewire\/(?:livewire|volt)"\s*:/
    IMPORT_RE   = /\bLivewire\\(?:Volt\\)?Component\b/

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "composer.json"
        return file_contents.matches?(COMPOSER_RE)
      end
      Noir::FileExtension.fold(filename).ends_with?(".php") && file_contents.includes?("Livewire\\") &&
        file_contents.matches?(IMPORT_RE)
    end
  end
end
