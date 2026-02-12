require "../../../models/detector"
require "../../../utils/json"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class ZapSitesTree < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = false
      if (filename.ends_with?(".yaml") || filename.ends_with?(".yml")) && valid_yaml?(file_contents)
        data = YAML.parse(file_contents)
        begin
          if data[0]["node"].as_s.includes? "Sites"
            check = true
            locator = CodeLocator.instance
            locator.push("zap-sites-tree", filename)
          end
        rescue
        end
      end

      check
    end

    def set_name
      @name = "zap_sites_tree"
    end
  end
end
