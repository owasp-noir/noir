require "../../models/analyzer"

class AnalyzerRails < Analyzer
  def analyze
    # Public Dir Analysis
    Dir.glob("#{@base_path}/public/**/*") do |file|
      next if File.directory?(file)
      relative_path = file.sub("#{@base_path}/public/", "")
      @result << Endpoint.new("#{@url}/#{relative_path}", "GET")
    end

    # Config Analysis
    if File.exists?("#{@base_path}/config/routes.rb")
      File.open("#{@base_path}/config/routes.rb", "r") do |file|
        file.each_line do |line|
          stripped_line = line.strip
          if stripped_line.size > 0 && stripped_line[0] != '#'
            line.scan(/resources?\s+:.*/) do |match|
              splited = match[0].split(":")
              if splited.size > 1
                resource = splited[1].split(",")[0]

                @result += controller_to_endpoint("#{@base_path}/app/controllers/#{resource}_controller.rb", @url, resource)
                @result += controller_to_endpoint("#{@base_path}/app/controllers/#{resource}s_controller.rb", @url, resource)
                @result += controller_to_endpoint("#{@base_path}/app/controllers/#{resource}es_controller.rb", @url, resource)
              end
            end

            line.scan(/get\s+['"](.+?)['"]/) do |match|
              @result << Endpoint.new("#{@url}#{match[1]}", "GET")
            end
            line.scan(/post\s+['"](.+?)['"]/) do |match|
              @result << Endpoint.new("#{@url}#{match[1]}", "POST")
            end
            line.scan(/put\s+['"](.+?)['"]/) do |match|
              @result << Endpoint.new("#{@url}#{match[1]}", "PUT")
            end
            line.scan(/delete\s+['"](.+?)['"]/) do |match|
              @result << Endpoint.new("#{@url}#{match[1]}", "DELETE")
            end
            line.scan(/patch\s+['"](.+?)['"]/) do |match|
              @result << Endpoint.new("#{@url}#{match[1]}", "PATCH")
            end
          end
        end
      end
    end

    @result
  end

  def controller_to_endpoint(path : String, @url : String, resource : String)
    @result = [] of Endpoint

    if File.exists?(path)
      File.open(path, "r") do |controller_file|
        param_type = "form"
        params_query = [] of Param
        params_body = [] of Param
        methods = [] of String

        controller_content = controller_file.gets_to_end
        if controller_content.includes? "render json:"
          param_type = "json"
        end

        controller_file.rewind
        controller_file.each_line do |controller_line|
          if controller_line.includes? "def "
            func_name = controller_line.split("def ")[1].split("(")[0]
            case func_name
            when "index"
              methods << "GET/INDEX"
            when "show"
              methods << "GET/SHOW"
            when "create"
              methods << "POST"
            when "update"
              methods << "PUT"
            when "destroy"
              methods << "DELETE"
            end
          end

          if controller_line.includes? "params.require"
            splited_param = controller_line.strip.split("permit")
            if splited_param.size > 1
              tparam = splited_param[1].gsub("(", "").gsub(")", "").gsub("s", "").gsub(":", "")
              tparam.split(",").each do |param|
                params_body << Param.new(param.strip, "", param_type)
                params_query << Param.new(param.strip, "", "query")
              end
            end
          end

          if controller_line.includes? "params[:"
            splited_param = controller_line.strip.split("params[:")[1]
            if splited_param
              param = splited_param.split("]")[0]
              params_body << Param.new(param.strip, "", param_type)
              params_query << Param.new(param.strip, "", "query")
            end
          end
        end

        deduplication_params_query = [] of Param
        get_param_duplicated : Array(String) = [] of String

        params_query.each do |get_param|
          if get_param_duplicated.includes? get_param.name
            deduplication_params_query << get_param
          else
            get_param_duplicated << get_param.name
          end
        end

        methods.each do |method|
          if method == "GET/INDEX"
            @result << Endpoint.new("#{@url}/#{resource}", "GET", deduplication_params_query)
          elsif method == "GET/SHOW"
            @result << Endpoint.new("#{@url}/#{resource}/1", "GET", deduplication_params_query)
          else
            if method == "POST"
              @result << Endpoint.new("#{@url}/#{resource}", method, params_body)
            else
              @result << Endpoint.new("#{@url}/#{resource}/1", method, params_body)
            end
          end
        end
      end
    end

    @result
  end
end

def analyzer_rails(options : Hash(Symbol, String))
  instance = AnalyzerRails.new(options)
  instance.analyze
end
