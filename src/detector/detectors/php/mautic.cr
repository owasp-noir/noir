require "../../../models/detector"

module Detector::Php
  # Mautic is a Symfony app, but it registers every route through a bespoke
  # per-bundle `Config/config.php` array (`'routes' => ['main'|'public'|'api'
  # => ['name' => ['path' => '/x', 'controller' => '...']]]`) rather than
  # Symfony attributes/annotations — so the Symfony analyzer finds nothing.
  class Mautic < Detector
    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "composer.json" || File.basename(filename) == "composer.lock"
        return true if file_contents.includes?(%("mautic/core-lib"))
      end

      # A bundle route config: `.../Config/config.php` carrying a `'routes'`
      # array of `Mautic\…Controller` handlers.
      if filename.includes?("Config/config.php") && filename.ends_with?(".php")
        return true if file_contents.includes?("'routes'") && file_contents.includes?("Mautic\\")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".php") || File.basename(filename) == "composer.json" || File.basename(filename) == "composer.lock"
    end

    def set_name
      @name = "php_mautic"
    end
  end
end
