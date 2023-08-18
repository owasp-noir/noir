require "../../models/analyzer"

class AnalyzerOAS3 < Analyzer
  def analyze
    locator = CodeLocator.instance
    oas3_json = locator.get("oas3-json")
    oas3_yaml = locator.get("oas3-yaml")

    if !oas3_json.nil?
      if File.exists?(oas3_json)
        content = File.read(oas3_json, encoding: "utf-8", invalid: :skip)
        json_obj = JSON.parse(content)

        base_path = @url
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
              @result << Endpoint.new(base_path + path, method.upcase, params_body)
            else
              @result << Endpoint.new(base_path + path, method.upcase)
            end
          end
        end
      end
    end

    if !oas3_yaml.nil?
      if File.exists?(oas3_yaml)
        content = File.read(oas3_yaml, encoding: "utf-8", invalid: :skip)
        yaml_obj = YAML.parse(content)
        base_path = @url
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
              @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase, params_body)
            else
              @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase)
            end
          end
        end
      end
    end

    @result
  end
end

def analyzer_oas3(options : Hash(Symbol, String))
  instance = AnalyzerOAS3.new(options)
  instance.analyze
end
