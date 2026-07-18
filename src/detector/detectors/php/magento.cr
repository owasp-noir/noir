require "../../../models/detector"

module Detector::Php
  class Magento < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # composer.json requiring a Magento distribution / framework.
      if base == "composer.json" &&
         (file_contents.includes?("magento/product-community-edition") ||
         file_contents.includes?("magento/product-enterprise-edition") ||
         file_contents.includes?("magento/magento2-base") ||
         file_contents.includes?("magento/framework") ||
         file_contents.includes?("magento/magento-cloud-metapackage"))
        return true
      end

      # Module registration entrypoint.
      if base == "registration.php" && file_contents.includes?("ComponentRegistrar")
        return true
      end

      # Module declaration: etc/module.xml with a Magento module node.
      if base == "module.xml" && file_contents.includes?("Magento\\Framework\\Module")
        return true
      end
      if base == "module.xml" && file_contents.includes?("<module") &&
         (file_contents.includes?("Magento_") || filename.includes?("/Magento/"))
        return true
      end

      # Magento Web API declaration.
      if base == "webapi.xml" && file_contents.includes?("<route") && file_contents.includes?("url=")
        return true
      end

      # Magento frontController route declaration.
      if base == "routes.xml" &&
         (file_contents.includes?("frontName") || file_contents.includes?("<router"))
        return true
      end

      # PHP source in the Magento namespace.
      if filename.ends_with?(".php") &&
         (file_contents.includes?("use Magento\\") || file_contents.includes?("namespace Magento\\"))
        return true
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".php") || filename.ends_with?(".xml") ||
        File.basename(filename) == "composer.json"
    end

    def set_name
      @name = "php_magento"
    end
  end
end
