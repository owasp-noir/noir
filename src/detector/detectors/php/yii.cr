require "../../../models/detector"

module Detector::Php
  class Yii < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check for composer.json with Yii2 dependency
      if filename.ends_with?("composer.json") && file_contents.includes?("yiisoft/yii2")
        return true
      end

      # Check for Yii2 vendor path
      if filename.includes?("vendor/yiisoft/")
        return true
      end

      # Check for Yii.php bootstrap file
      if filename.ends_with?("Yii.php") && file_contents.includes?("class Yii")
        return true
      end

      # Check for use yii\... or use Yii; imports in PHP files
      if filename.ends_with?(".php")
        if file_contents.match(/(?:^|\n|<\?php\s+)\s*use\s+yii\\[^;\n]*;/)
          return true
        end

        if file_contents.match(/(?:^|\n|<\?php\s+)\s*use\s+Yii\s*;/)
          return true
        end

        # Class inheritance from yii web/rest controllers
        if file_contents.match(/extends\s+(?:\\?yii\\(?:web|rest)\\(?:Active)?Controller)/)
          return true
        end
      end

      false
    end

    def set_name
      @name = "php_yii"
    end
  end
end
