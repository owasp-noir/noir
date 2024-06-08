require "../../models/analyzer"

class AnalyzerRAML < Analyzer
  def analyze
    locator = CodeLocator.instance
    raml_specs = locator.all("raml-spec")

    if raml_specs.is_a?(Array(String))
      raml_specs.each do |raml_spec|
        if File.exists?(raml_spec)
          details = Details.new(PathInfo.new(raml_spec))

          content = File.read(raml_spec, encoding: "utf-8", invalid: :skip)
          yaml_obj = YAML.parse(content)
          yaml_obj.as_h.each do |path, path_obj|
            begin
              path_obj.as_h.each do |method, method_obj|
                params = [] of Param

                if method_obj.as_h.has_key? "queryParameters"
                  method_obj["queryParameters"].as_h.each do |param_name, _|
                    param = Param.new(param_name.to_s, "", "query")
                    params << param
                  end
                end

                if method_obj.as_h.has_key? "body"
                  method_obj["body"].as_h.each do |content_type, content_obj|
                    if content_type == "application/json"
                      content_obj["example"].as_h.each do |param_name, _|
                        param = Param.new(param_name.to_s, "", "json")
                        params << param
                      end
                    elsif content_type == "application/x-www-form-urlencoded"
                      content_obj["example"].as_h.each do |param_name, _|
                        param = Param.new(param_name.to_s, "", "form")
                        params << param
                      end
                    end
                  end
                end

                if method_obj.as_h.has_key? "headers"
                  method_obj["headers"].as_h.each do |param_name, _|
                    param = Param.new(param_name.to_s, "", "header")
                    params << param
                  end
                end

                @result << Endpoint.new(path.to_s, method.to_s.upcase, params, details)
              rescue e
                @logger.debug "Exception of #{raml_spec}/paths/#{path}/#{method}"
                @logger.debug_sub e
              end
            rescue e
              @logger.debug "Exception of #{raml_spec}/paths/#{path}"
              @logger.debug_sub e
            end
          end
        end
      end
    end

    @result
  end
end

def analyzer_raml(options : Hash(String, String))
  instance = AnalyzerRAML.new(options)
  instance.analyze
end
