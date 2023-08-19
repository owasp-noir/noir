require "../../models/analyzer"

class AnalyzerOAS3 < Analyzer
  def get_base_path(servers)
    base_path = @url
    servers.as_a.each do |server_obj|
      if server_obj["url"].to_s.starts_with?("http")
        user_uri = URI.parse(@url)
        source_uri = URI.parse(server_obj["url"].to_s)
        if user_uri.host == source_uri.host
          base_path = @url + source_uri.path
          break
        end
      end
    end

    base_path
  end

  def analyze
    locator = CodeLocator.instance
    oas3_json = locator.get("oas3-json")
    oas3_yaml = locator.get("oas3-yaml")

    if !oas3_json.nil?
      if File.exists?(oas3_json)
        content = File.read(oas3_json, encoding: "utf-8", invalid: :skip)
        json_obj = JSON.parse(content)

        base_path = get_base_path json_obj["servers"]

        json_obj["paths"].as_h.each do |path, path_obj|
          path_obj.as_h.each do |method, method_obj|
            params = [] of Param

            if method_obj.is_a?(JSON::Any) && method_obj.is_a?(Hash(String, JSON::Any))
              if method_obj.as_h.has_key?("parameters")
                method_obj["parameters"].as_a.each do |param_obj|
                  param_name = param_obj["name"].to_s
                  if param_obj["in"] == "query"
                    param = Param.new(param_name, "", "query")
                    params << param
                  elsif param_obj["in"] == "header"
                    param = Param.new(param_name, "", "header")
                    params << param
                  end
                end
              end

              if method_obj.as_h.has_key?("requestBody")
                method_obj["requestBody"]["content"].as_h.each do |content_type, content_obj|
                  if content_type == "application/json"
                    content_obj["schema"]["properties"].as_h.each do |param_name, _|
                      param = Param.new(param_name, "", "json")
                      params << param
                    end
                  elsif content_type == "application/x-www-form-urlencoded"
                    content_obj["schema"]["properties"].as_h.each do |param_name, _|
                      param = Param.new(param_name, "", "form")
                      params << param
                    end
                  end
                end
              end
            end

            if params.size > 0 && params.size > 0
              @result << Endpoint.new(base_path + path, method.upcase, params + params)
            elsif params.size > 0
              @result << Endpoint.new(base_path + path, method.upcase, params)
            elsif params.size > 0
              @result << Endpoint.new(base_path + path, method.upcase, params)
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
        base_path = get_base_path yaml_obj["servers"]

        yaml_obj["paths"].as_h.each do |path, path_obj|
          path_obj.as_h.each do |method, method_obj|
            params = [] of Param

            if method_obj.is_a?(YAML::Any) && method_obj.is_a?(Hash(String, YAML::Any))
              if method_obj.as_h.has_key?("parameters")
                method_obj["parameters"].as_a.each do |param_obj|
                  param_name = param_obj["name"].to_s
                  if param_obj["in"] == "query"
                    param = Param.new(param_name, "", "query")
                    params << param
                  elsif param_obj["in"] == "header"
                    param = Param.new(param_name, "", "header")
                    params << param
                  end
                end
              end

              if method_obj.as_h.has_key?("requestBody")
                method_obj["requestBody"]["content"].as_h.each do |content_type, content_obj|
                  if content_type == "application/json"
                    content_obj["schema"]["properties"].as_h.each do |param_name, _|
                      param = Param.new(param_name.to_s, "", "json")
                      params << param
                    end
                  elsif content_type == "application/x-www-form-urlencoded"
                    content_obj["schema"]["properties"].as_h.each do |param_name, _|
                      param = Param.new(param_name.to_s, "", "form")
                      params << param
                    end
                  end
                end
              end
            end

            if params.size > 0 && params.size > 0
              @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase, params + params)
            elsif params.size > 0
              @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase, params)
            elsif params.size > 0
              @result << Endpoint.new(base_path + path.to_s, method.to_s.upcase, params)
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
