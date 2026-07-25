require "../../../models/detector"

module Detector::Php
  class Drupal < Detector
    detector_for "php_drupal",
      extensions: %w[.php .module .install .theme .profile .inc .yml .yaml],
      basenames: %w[composer.json]

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # composer.json requiring Drupal core / recommended project.
      if base == "composer.json" &&
         (file_contents.includes?("drupal/core") ||
         file_contents.includes?("drupal/recommended-project") ||
         file_contents.includes?("drupal/legacy-project"))
        return true
      end

      # Drupal 8+ routing files: `MODULE.routing.yml`.
      if filename.ends_with?(".routing.yml") || filename.ends_with?(".routing.yaml")
        return true
      end

      # Extension metadata: `MODULE.info.yml` declaring a Drupal project.
      if (filename.ends_with?(".info.yml") || filename.ends_with?(".info.yaml")) &&
         (file_contents.includes?("core_version_requirement") ||
         file_contents.includes?("type: module") ||
         file_contents.includes?("type: theme") ||
         file_contents.includes?("type: profile"))
        return true
      end

      # Drupal-specific hook file extensions. Gate on PHP content — a bare
      # extension match would tag unrelated repos (a Heroku shell `.profile`,
      # a freedesktop INI `index.theme`, an Arch `pkg.install`) as Drupal.
      # Real Drupal `.module`/`.install`/`.theme`/`.profile` files always
      # open with `<?php`.
      if (filename.ends_with?(".module") || filename.ends_with?(".install") ||
         filename.ends_with?(".theme") || filename.ends_with?(".profile")) &&
         (file_contents.includes?("<?php") || file_contents.includes?("Drupal") ||
         file_contents.includes?("hook_"))
        return true
      end

      # PHP source using the Drupal namespace.
      if filename.ends_with?(".php") &&
         (file_contents.includes?("use Drupal\\") ||
         file_contents.includes?("namespace Drupal\\") ||
         file_contents.includes?("extends ControllerBase"))
        return true
      end

      false
    end
  end
end
