require "../../../models/detector"

module Detector::Php
  class CakePHP < Detector
    detector_for "php_cakephp",
      extensions: %w[.php .phtml],
      basenames: %w[composer.json composer.lock cake]

    def detect(filename : String, file_contents : String) : Bool
      # Check for composer.json with CakePHP dependency
      if filename.ends_with?("composer.json") && file_contents.includes?("cakephp/cakephp")
        return true
      end

      # Check for CakePHP console script
      if File.basename(filename) == "cake" || File.basename(filename) == "cake.php"
        if file_contents.includes?("Cake") || file_contents.includes?("cake")
          return true
        end
      end

      # Check for CakePHP config/routes.php
      if filename.includes?("config/routes.php")
        if file_contents.includes?("Cake\\Routing\\RouteBuilder") || file_contents.includes?("$routes->connect") || file_contents.includes?("$builder->connect")
          return true
        end
      end

      false
    end
  end
end
