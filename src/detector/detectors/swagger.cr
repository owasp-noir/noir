require "../../models/detector"
require "../../utils/json"
require "../../utils/yaml"

class DetectorSwagger < Detector
  def detect(filename : String, file_contents : String) : Bool
    check = false
    if valid_json? file_contents
      data = JSON.parse(file_contents)
      if !data["swagger"].nil?
        check = true
      end
    elsif valid_yaml? file_contents
      data = YAML.parse(file_contents)
      if !data["swagger"].nil?
        check = true
      end
    end

    check
  end

  def set_name
    @name = "swagger"
  end
end
