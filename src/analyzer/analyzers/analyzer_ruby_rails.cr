require "../../models/analyzer"

class AnalyzerRubyRails < Analyzer
  def analyze
    # Public Dir Analysis
    begin
      Dir.glob("#{@base_path}/public/**/*") do |file|
        next if File.directory?(file)
        real_path = "#{@base_path}/public/".gsub(/\/+/, '/')
        relative_path = file.sub(real_path, "")
        details = Details.new(PathInfo.new(file))
        @result << Endpoint.new("/#{relative_path}", "GET", details)
      end
    rescue e
      logger.debug e
    end

    # Config Analysis
    if File.exists?("#{@base_path}/config/routes.rb")
      File.open("#{@base_path}/config/routes.rb", "r", encoding: "utf-8", invalid: :skip) do |file|
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

            details = Details.new(PathInfo.new("#{@base_path}/config/routes.rb"))
            line.scan(/get\s+['"](.+?)['"]/) do |match|
              @result << Endpoint.new("#{match[1]}", "GET", details)
            end
            line.scan(/post\s+['"](.+?)['"]/) do |match|
              @result << Endpoint.new("#{match[1]}", "POST", details)
            end
            line.scan(/put\s+['"](.+?)['"]/) do |match|
              @result << Endpoint.new("#{match[1]}", "PUT", details)
            end
            line.scan(/delete\s+['"](.+?)['"]/) do |match|
              @result << Endpoint.new("#{match[1]}", "DELETE", details)
            end
            line.scan(/patch\s+['"](.+?)['"]/) do |match|
              @result << Endpoint.new("#{match[1]}", "PATCH", details)
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
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |controller_file|
        param_type = "form"
        params_query = [] of Param
        params_body = [] of Param
        params_method = Hash(String, Array(Param)).new
        methods = [] of String
        this_method = ""

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
              this_method = func_name
            when "show"
              methods << "GET/SHOW"
              this_method = func_name
            when "create"
              methods << "POST"
              this_method = func_name
            when "update"
              methods << "PUT"
              this_method = func_name
            when "destroy"
              methods << "DELETE"
              this_method = func_name
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

          if controller_line.includes? "request.headers["
            splited_param = controller_line.strip.split("request.headers[")[1]
            if splited_param
              param = splited_param.split("]")[0].gsub("'", "").gsub("\"", "")
              param_line = Param.new(param.strip, "", "header")
              if params_method.has_key? this_method
                params_method[this_method] << param_line
              else
                params_method[this_method] = [] of Param
                params_method[this_method] << param_line
              end
            end
          end

          if controller_line.includes? "cookies[:"
            splited_param = controller_line.strip.split("cookies[:")[1]
            if splited_param
              param = splited_param.split("]")[0].gsub("'", "").gsub("\"", "")
              if this_method != ""
                param_line = Param.new(param.strip, "", "cookie")
                if params_method.has_key? this_method
                  params_method[this_method] << param_line
                else
                  params_method[this_method] = [] of Param
                  params_method[this_method] << param_line
                end
              end
            end
          end

          if controller_line.includes? "cookies.signed[:"
            splited_param = controller_line.strip.split("cookies.signed[:")[1]
            if splited_param
              param = splited_param.split("]")[0].gsub("'", "").gsub("\"", "")
              if this_method != ""
                param_line = Param.new(param.strip, "", "cookie")
                if params_method.has_key? this_method
                  params_method[this_method] << param_line
                else
                  params_method[this_method] = [] of Param
                  params_method[this_method] << param_line
                end
              end
            end
          end

          if controller_line.includes? "cookies.encrypted[:"
            splited_param = controller_line.strip.split("cookies.encrypted[:")[1]
            if splited_param
              param = splited_param.split("]")[0].gsub("'", "").gsub("\"", "")
              if this_method != ""
                param_line = Param.new(param.strip, "", "cookie")
                if params_method.has_key? this_method
                  params_method[this_method] << param_line
                else
                  params_method[this_method] = [] of Param
                  params_method[this_method] << param_line
                end
              end
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

        details = Details.new(PathInfo.new(path))
        methods.each do |method|
          if method == "GET/INDEX"
            if params_method.has_key? "index"
              index_params = [] of Param
              params_method["index"].each do |param|
                index_params << param
              end
            end

            index_params ||= [] of Param
            deduplication_params_query ||= [] of Param
            last_params = index_params + deduplication_params_query
            @result << Endpoint.new("/#{resource}", "GET", last_params, details)
          elsif method == "GET/SHOW"
            if params_method.has_key? "show"
              show_params = [] of Param
              params_method["show"].each do |param|
                show_params << param
              end
            end
            show_params ||= [] of Param
            deduplication_params_query ||= [] of Param
            last_params = show_params + deduplication_params_query
            @result << Endpoint.new("/#{resource}/1", "GET", last_params, details)
          else
            if method == "POST"
              if params_method.has_key? "create"
                create_params = [] of Param
                params_method["create"].each do |param|
                  create_params << param
                end
              end
              create_params ||= [] of Param
              params_body ||= [] of Param
              last_params = create_params + params_body
              @result << Endpoint.new("/#{resource}", method, last_params, details)
            elsif method == "DELETE"
              params_delete = [] of Param
              if params_method.has_key? "delete"
                params_method["delete"].each do |param|
                  params_delete << param
                end
              end
              @result << Endpoint.new("/#{resource}/1", method, params_delete, details)
            else
              if params_method.has_key? "update"
                update_params = [] of Param
                params_method["update"].each do |param|
                  update_params << param
                end
              end
              update_params ||= [] of Param
              params_body ||= [] of Param
              last_params = update_params + params_body
              @result << Endpoint.new("/#{resource}/1", method, last_params, details)
            end
          end
        end
      end
    end

    @result
  end
end

def analyzer_ruby_rails(options : Hash(String, YAML::Any))
  instance = AnalyzerRubyRails.new(options)
  instance.analyze
end
