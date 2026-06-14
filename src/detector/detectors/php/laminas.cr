require "../../../models/detector"

module Detector::Php
  class Laminas < Detector
    LAMINAS_PACKAGES = [
      "laminas/laminas-mvc",
      "laminas/laminas-router",
      "mezzio/mezzio",
      "mezzio/mezzio-router",
      "zendframework/zend-mvc",
      "zendframework/zend-router",
      "zendframework/zend-expressive",
    ]

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "composer.json" || File.basename(filename) == "composer.lock"
        # Match the package as a complete quoted name (`"mezzio/mezzio"`), not a
        # bare substring. A loose `includes?("mezzio/mezzio")` matched the Swoole
        # server adapter `mezzio/mezzio-swoole` (a transitive dep of many
        # Laravel/Symfony/Yii apps), and the blanket `"zendframework/"` matched
        # non-routing PSR-7 deps like `zendframework/zend-diactoros` — both fired
        # the Laminas analyzer on apps that never use Laminas routing, surfacing
        # HTTP-client `$x->get('https://…')` calls as phantom endpoints.
        return true if LAMINAS_PACKAGES.any? { |package| file_contents.includes?(%("#{package}")) }
      end

      if filename.ends_with?(".php")
        return true if file_contents.match(/(?:^|\n|<\?php\s+)\s*use\s+(?:Laminas|Zend)\\(?:Mvc|Router)\\[^;\n]*;/)
        return true if file_contents.match(/(?:^|\n|<\?php\s+)\s*use\s+Mezzio\\[^;\n]*;/)
        return true if file_contents.includes?("Laminas\\Router\\RouteStackInterface")
        return true if file_contents.includes?("Zend\\Router\\RouteStackInterface")
        return true if file_contents.includes?("Mezzio\\Application")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".php") || filename.ends_with?(".phtml") || File.basename(filename) == "composer.json" || File.basename(filename) == "composer.lock"
    end

    def set_name
      @name = "php_laminas"
    end
  end
end
