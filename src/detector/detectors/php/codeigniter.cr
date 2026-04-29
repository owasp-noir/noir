require "../../../models/detector"

module Detector::Php
  class CodeIgniter < Detector
    def detect(filename : String, file_contents : String) : Bool
      # composer.json with CodeIgniter dependency
      if filename.ends_with?("composer.json") &&
         (file_contents.includes?("codeigniter4/framework") ||
         file_contents.includes?("codeigniter4/codeigniter4") ||
         file_contents.includes?("codeigniter/framework"))
        return true
      end

      # CodeIgniter 4 CLI script
      if filename.ends_with?("/spark") || filename == "spark"
        if file_contents.includes?("CodeIgniter") || file_contents.includes?("Config\\Paths")
          return true
        end
      end

      # CodeIgniter 4 routes file: app/Config/Routes.php
      if filename.includes?("Config/Routes.php")
        if file_contents.includes?("CodeIgniter\\Router") ||
           file_contents.includes?("Services::routes()") ||
           file_contents.includes?("$routes->")
          return true
        end
      end

      # CodeIgniter 3 routes file: application/config/routes.php
      if filename.includes?("application/config/routes.php")
        if file_contents.includes?("$route[")
          return true
        end
      end

      # PHP files with CodeIgniter namespaces
      if filename.ends_with?(".php") &&
         (file_contents.includes?("use CodeIgniter\\") ||
         file_contents.includes?("namespace CodeIgniter\\") ||
         file_contents.includes?("extends \\CodeIgniter\\Controller") ||
         file_contents.includes?("extends CodeIgniter\\Controller") ||
         file_contents.includes?("extends ResourceController") &&
         file_contents.includes?("CodeIgniter\\RESTful"))
        return true
      end

      false
    end

    def set_name
      @name = "php_codeigniter"
    end
  end
end
