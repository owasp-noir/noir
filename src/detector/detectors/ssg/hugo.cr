require "../../../models/detector"
require "toml"

class DetectorHugo < Detector
  def detect(filename : String, file_contents : String) : Bool
    locator = CodeLocator.instance

    # Check for Hugo
    if filename.includes? "hugo.toml"
      toml = TOML.parse(file_contents)

      if !toml["baseURL"].nil?
        if toml["baseURL"].to_s == "" || toml["baseURL"].to_s == "/"
          locator.push("hugo-baseurl", "/")
        else
          locator.push("hugo-baseurl", toml["baseURL"].to_s)
        end

        true
      else
        false
      end
    else
      false
    end
  end

  def set_name
    @name = "hugo"
  end
end
