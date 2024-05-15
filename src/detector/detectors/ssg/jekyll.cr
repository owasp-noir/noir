require "../../../models/detector"

class DetectorJekyll < Detector
  def detect(filename : String, file_contents : String) : Bool
    locator = CodeLocator.instance

    # Push basepath
    if (filename.includes? "_config.yml") || (filename.includes? "_config.yaml")
      begin
        yaml = YAML.parse(file_contents)
        if !yaml["baseurl"].nil?
          if yaml["baseurl"].to_s == "" || yaml["baseurl"].to_s == "/"
            locator.push("jekyll-basepath", "/")
          else
            locator.push("jekyll-basepath", yaml["baseurl"].to_s)
          end
        end
      rescue
      end
    end

    # Check for Jekyll
    if (filename.includes? "Gemfile") && (file_contents.includes? "jekyll")
      true
    else
      false
    end
  end

  def set_name
    @name = "jekyll"
  end
end
