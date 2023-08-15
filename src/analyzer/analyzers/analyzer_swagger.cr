require "../../models/analyzer"

class AnalyzerSwagger < Analyzer
  def analyze
    locator = CodeLocator.instance
    swagger_json = locator.get("swagger-json")
    swagger_yaml = locator.get("swagger-yaml")

    if !swagger_json.nil?
      if File.exists?(swagger_json)
        content = File.read(swagger_json, encoding: "utf-8", invalid: :skip)
        json_obj = JSON.parse(content)
        json_obj["paths"].as_h.each do |path, path_obj|
          path_obj.as_h.each do |method, method_obj|
            params_query = [] of Param
            params_body = [] of Param

            if method_obj.as_h.has_key?("parameters")
              method_obj["parameters"].as_a.each do |param_obj|
                param_name = param_obj["name"].to_s
                if param_obj["in"] == "query"
                  param = Param.new(param_name, "", "query")
                  params_query << param
                elsif param_obj["in"] == "body"
                  param = Param.new(param_name, "", "json")
                  params_body << param
                elsif param_obj["in"] == "formData"
                  param = Param.new(param_name, "", "form")
                  params_body << param
                end
              end
              @result << Endpoint.new(path, method.upcase, params_body)
            else
              @result << Endpoint.new(path, method.upcase)
            end
          end
        end
      end
    end

    if !swagger_yaml.nil?
      if File.exists?(swagger_yaml)
        content = File.read(swagger_yaml, encoding: "utf-8", invalid: :skip)
        yaml_obj = YAML.parse(content)
        yaml_obj["paths"].as_h.each do |path, path_obj|
          path_obj.as_h.each do |method, method_obj|
            params_query = [] of Param
            params_body = [] of Param

            if method_obj.as_h.has_key?("parameters")
              method_obj["parameters"].as_a.each do |param_obj|
                param_name = param_obj["name"].to_s
                if param_obj["in"] == "query"
                  param = Param.new(param_name, "", "query")
                  params_query << param
                elsif param_obj["in"] == "body"
                  param = Param.new(param_name, "", "json")
                  params_body << param
                elsif param_obj["in"] == "formData"
                  param = Param.new(param_name, "", "form")
                  params_body << param
                end
              end
              @result << Endpoint.new(path.to_s, method.to_s.upcase, params_body)
            else
              @result << Endpoint.new(path.to_s, method.to_s.upcase)
            end
          end
        end
      end
    end

    @result
  end
end

def analyzer_swagger(options : Hash(Symbol, String))
  instance = AnalyzerSwagger.new(options)
  instance.analyze
end
