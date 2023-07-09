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

        controller_content = controller_file.gets_to_end
        if controller_content.includes? "render json:"
          param_type = "json"
        end

        controller_file.rewind
        controller_file.each_line do |controller_line|
          controller_line.strip.scan(/params\[:.*.]/) do |param_match|
            param = param_match[0].gsub(/\[|\]/, "").split(":")[1].strip

            params_query << Param.new(param, "", "query")
            params_body << Param.new(param, "", param_type)
          end
        end

        @result << Endpoint.new("#{@url}/#{resource}", "GET", params_query)
        @result << Endpoint.new("#{@url}/#{resource}", "POST", params_body)
        @result << Endpoint.new("#{@url}/#{resource}/1", "GET", params_query)
        @result << Endpoint.new("#{@url}/#{resource}/1", "PUT", params_body)
        @result << Endpoint.new("#{@url}/#{resource}/1", "DELETE", params_query)
        @result << Endpoint.new("#{@url}/#{resource}/1", "PATCH", params_body)
      end
    end

    @result
  end
end

def analyzer_rails(options : Hash(Symbol, String))
  instance = AnalyzerRails.new(options)
  instance.analyze
end
