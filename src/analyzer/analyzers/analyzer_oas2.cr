require "../../models/analyzer"

class AnalyzerOAS2 < Analyzer
  def analyze
    locator = CodeLocator.instance
    swagger_jsons = locator.all("swagger-json")
    swagger_yamls = locator.all("swagger-yaml")

    if swagger_jsons.is_a?(Array(String))
      swagger_jsons.each do |swagger_json|
        if File.exists?(swagger_json)
          details = Details.new(PathInfo.new(swagger_json))
          content = File.read(swagger_json, encoding: "utf-8", invalid: :skip)
          json_obj = JSON.parse(content)
          base_path = ""
          begin
            if json_obj["basePath"].to_s != ""
              base_path = json_obj["basePath"].to_s
            end
          rescue e
            @logger.debug "Exception of #{swagger_json}/basePath"
            @logger.debug_sub e
          end

          begin
            paths = json_obj["paths"].as_h
            paths.each do |path, path_obj|
              path_obj.as_h.each do |method, method_obj|
                params = [] of Param

                if method_obj.as_h.has_key?("parameters")
                  method_obj["parameters"].as_a.each do |param_obj|
                    param_name = param_obj["name"].to_s
                    if param_obj["in"] == "query"
                      param = Param.new(param_name, "", "query")
                      params << param
                    elsif param_obj["in"] == "form"
                      param = Param.new(param_name, "", "json")
                      params << param
                    elsif param_obj["in"] == "formData"
                      param = Param.new(param_name, "", "form")
                      params << param
                    elsif param_obj["in"] == "header"
                      param = Param.new(param_name, "", "header")
                      params << param
                    end
                  end
                  @result << Endpoint.new(base_path + path, method.upcase, params, details)
                else
                  @result << Endpoint.new(base_path + path, method.upcase, details)
                end
              rescue e
                @logger.debug "Exception of #{swagger_json}/paths/path/method"
                @logger.debug_sub e
              end
            rescue e
              @logger.debug "Exception of #{swagger_json}/paths/path"
              @logger.debug_sub e
            end
          rescue e
            @logger.debug "Exception of #{swagger_json}/paths"
            @logger.debug_sub e
          end
        end
      end
    end

    if swagger_yamls.is_a?(Array(String))
      swagger_yamls.each do |swagger_yaml|
        if File.exists?(swagger_yaml)
          details = Details.new(PathInfo.new(swagger_yaml))
          content = File.read(swagger_yaml, encoding: "utf-8", invalid: :skip)
          yaml_obj = YAML.parse(content)
          base_path = ""
          begin
            if yaml_obj["basePath"].to_s != ""
              base_path = yaml_obj["basePath"].to_s
            end
          rescue e
            @logger.debug "Exception of #{swagger_yaml}/basePath"
            @logger.debug_sub e
          end

          begin
            paths = yaml_obj["paths"].as_h
            paths.each do |path, path_obj|
              path_obj.as_h.each do |method, method_obj|
                params = [] of Param

                if method_obj.as_h.has_key?("parameters")
                  method_obj["parameters"].as_a.each do |param_obj|
                    param_name = param_obj["name"].to_s
                    if param_obj["in"] == "query"
                      param = Param.new(param_name, "", "query")
                      params << param
                    elsif param_obj["in"] == "form"
                      param = Param.new(param_name, "", "json")
                      params << param
                    elsif param_obj["in"] == "formData"
                      param = Param.new(param_name, "", "form")
                      params << param
                    elsif param_obj["in"] == "header"
                      param = Param.new(param_name, "", "header")
                      params << param
                    end
                  end
                  @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase, params, details)
                else
                  @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase, details)
                end
              rescue e
                @logger.debug "Exception of #{swagger_yaml}/paths/path/method"
                @logger.debug_sub e
              end
            rescue e
              @logger.debug "Exception of #{swagger_yaml}/paths/path"
              @logger.debug_sub e
            end
          rescue e
            @logger.debug "Exception of #{swagger_yaml}/paths"
            @logger.debug_sub e
          end
        end
      end
    end

    @result
  end
end

def analyzer_oas2(options : Hash(String, String))
  instance = AnalyzerOAS2.new(options)
  instance.analyze
end
