require "../../../models/detector"

module Detector::Php
  class CakePHP < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check for composer.json with CakePHP dependency
      if filename.ends_with?("composer.json") && file_contents.includes?("cakephp/cakephp")
        return true
      end

      # Check for CakePHP console script
      if filename.ends_with?("bin/cake") || filename.ends_with?("bin/cake.php")
        return true
      end

      # Check for CakePHP config/routes.php
      if filename.includes?("config/routes.php")
        if file_contents.includes?("Cake\\Routing\\RouteBuilder") || file_contents.includes?("$routes->connect") || file_contents.includes?("$builder->connect")
          return true
        end
      end

      false
    end

    def set_name
      @name = "php_cakephp"
    end
  end
end
