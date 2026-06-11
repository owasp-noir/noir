require "../../../models/detector"
require "../../../utils/yaml"
require "../../../utils/json"
require "../../../models/code_locator"

module Detector::Specification
  class AwsCloudformation < Detector
    SAM_TRANSFORM = "AWS::Serverless-2016-10-31"

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      detected = if filename.ends_with?(".json")
                   detect_json(file_contents)
                 else
                   detect_yaml(file_contents)
                 end

      CodeLocator.instance.push("aws-cloudformation-spec", filename) if detected
      detected
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".yaml") || filename.ends_with?(".yml") || filename.ends_with?(".json")
    end

    def set_name
      @name = "aws_cloudformation"
    end

    # Registers each template path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def detect_yaml(content : String) : Bool
      return false unless cloudformation_candidate?(content)

      data = YAML.parse(content)
      root = data.as_h?
      return false unless root

      return true if root.has_key?(YAML::Any.new("AWSTemplateFormatVersion"))
      transform = root[YAML::Any.new("Transform")]?
      transform_includes_sam?(transform)
    rescue
      false
    end

    private def detect_json(content : String) : Bool
      return false unless cloudformation_candidate?(content)

      data = JSON.parse(content)
      root = data.as_h?
      return false unless root

      return true if root.has_key?("AWSTemplateFormatVersion")
      transform = root["Transform"]?
      json_transform_includes_sam?(transform)
    rescue
      false
    end

    private def transform_includes_sam?(node : YAML::Any?) : Bool
      return false if node.nil?
      if str = node.as_s?
        return str.includes?(SAM_TRANSFORM)
      end
      if arr = node.as_a?
        return arr.any? { |item| transform_includes_sam?(item) }
      end
      false
    end

    private def json_transform_includes_sam?(node : JSON::Any?) : Bool
      return false if node.nil?
      if str = node.as_s?
        return str.includes?(SAM_TRANSFORM)
      end
      if arr = node.as_a?
        return arr.any? { |item| json_transform_includes_sam?(item) }
      end
      false
    end

    private def cloudformation_candidate?(content : String) : Bool
      content.includes?("AWSTemplateFormatVersion") || content.includes?(SAM_TRANSFORM)
    end
  end
end
