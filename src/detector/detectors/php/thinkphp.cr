require "../../../models/detector"

module Detector::Php
  class ThinkPHP < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check for composer.json with ThinkPHP dependency
      if filename.ends_with?("composer.json") && file_contents.includes?("topthink/framework")
        return true
      end

      # Check for think CLI script in the project root
      if File.basename(filename) == "think" && (file_contents.includes?("think\\App") || file_contents.includes?("think\\Console"))
        return true
      end

      # Check for routes/app.php or route/route.php
      if filename.includes?("route/route.php") || filename.includes?("route/app.php")
        return true
      end

      # Check for use think\... imports in PHP files
      if filename.ends_with?(".php")
        if file_contents.match(/(?:^|\n|<\?php\s+)\s*use\s+think\\[^;\n]*;/)
          return true
        end

        # Class inheritance from think base classes
        if file_contents.match(/extends\s+(?:\\?think\\(?:facade\\)?(?:Controller|App|Route))/)
          return true
        end
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".php") || filename.ends_with?(".phtml") || File.basename(filename) == "composer.json" || File.basename(filename) == "composer.lock" || File.basename(filename) == "think"
    end

    def set_name
      @name = "php_thinkphp"
    end
  end
end
