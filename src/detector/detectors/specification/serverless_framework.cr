require "../../../models/detector"
require "../../../utils/yaml"
require "../../../models/code_locator"

module Detector::Specification
  class ServerlessFramework < Detector
    CONFIG_FILES = {"serverless.yml", "serverless.yaml", "serverless.json"}

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      base = File.basename(filename)
      if base.ends_with?(".json")
        return false unless valid_json?(file_contents)
        begin
          return false unless serverless_doc?(JSON.parse(file_contents))
        rescue
          return false
        end
      else
        return false unless valid_yaml?(file_contents)
        begin
          return false unless serverless_doc?(YAML.parse(file_contents))
        rescue
          return false
        end
      end

      CodeLocator.instance.push("serverless-framework-spec", filename)
      true
    end

    def applicable?(filename : String) : Bool
      CONFIG_FILES.includes?(File.basename(filename))
    end

    def set_name
      @name = "serverless_framework"
    end

    # Registers each Serverless Framework config path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def serverless_doc?(data : JSON::Any) : Bool
      root = data.as_h?
      return false unless root
      has_service = root.has_key?("service")
      has_functions = root.has_key?("functions")
      has_provider = root.has_key?("provider")
      has_service && has_functions && has_provider
    rescue
      false
    end

    private def serverless_doc?(data : YAML::Any) : Bool
      root = data.as_h?
      return false unless root
      has_service = root.has_key?(YAML::Any.new("service"))
      has_functions = root.has_key?(YAML::Any.new("functions"))
      has_provider = root.has_key?(YAML::Any.new("provider"))
      has_service && has_functions && has_provider
    rescue
      false
    end
  end
end
