require "../../models/detector"
require "../../utils/json"
require "../../utils/yaml"
require "../../models/code_locator"

class DetectorSwagger < Detector
  def detect(filename : String, file_contents : String) : Bool
    check = false
    if valid_json? file_contents
      data = JSON.parse(file_contents)
      begin
        if !data["swagger"].nil?
          check = true
          locator = CodeLocator.instance
          locator.set("swagger-json", filename)
        end
      rescue
      end
    elsif valid_yaml? file_contents
      data = YAML.parse(file_contents)
      begin
        if !data["swagger"].nil?
          check = true
          locator = CodeLocator.instance
          locator.set("swagger-yaml", filename)
        end
      rescue
      end
    end

    check
  end

  def set_name
    @name = "swagger"
  end
end
