require "./logger"

class OutputBuilder
  @logger : NoirLogger
  @options : Hash(String, String)
  @is_debug : Bool
  @is_color : Bool
  @is_log : Bool
  @output_file : String

  def initialize(options : Hash(String, String))
    @is_debug = str_to_bool(options["debug"])
    @options = options
    @is_color = str_to_bool(options["color"])
    @is_log = str_to_bool(options["nolog"])
    @output_file = options["output"]

    @logger = NoirLogger.new @is_debug, @is_color, @is_log
  end

  def ob_puts(message)
    puts message
    if @output_file != ""
      File.open(@output_file, "a") do |file|
        file.puts message
      end
    end
  end

  def print
    # After inheriting the class, write an action code here.
  end

  def bake_endpoint(url : String, params : Array(Param))
    @logger.debug "Baking endpoint #{url} with #{params.size} params."

    final_url = url
    final_body = ""
    final_path_params = [] of String
    final_headers = [] of String
    final_cookies = [] of String
    final_tags = [] of String
    is_json = false
    first_query = true
    first_form = true

    if final_url.starts_with?("//")
      if final_url.size != 2 && final_url[2] != ':'
        final_url = final_url[1..]
      end
    end

    if !params.nil?
      params.each do |param|
        if param.param_type == "query"
          if first_query
            final_url += "?#{param.name}=#{param.value}"
            first_query = false
          else
            final_url += "&#{param.name}=#{param.value}"
          end
        end

        if param.param_type == "form"
          if first_form
            final_body += "#{param.name}=#{param.value}"
            first_form = false
          else
            final_body += "&#{param.name}=#{param.value}"
          end
        end

        if param.param_type == "path"
          final_path_params << "#{param.name}"
        end

        if param.param_type == "header"
          final_headers << "#{param.name}: #{param.value}"
        end

        if param.param_type == "cookie"
          final_cookies << "#{param.name}=#{param.value}"
        end

        if param.param_type == "json"
          is_json = true
        end

        if param.tags.size > 0
          param.tags.each do |tag|
            final_tags << tag.name
          end
        end
      end

      if is_json
        json_tmp = Hash(String, String).new

        params.each do |param|
          if param.param_type == "json"
            json_tmp[param.name] = param.value
          end
        end

        final_body = json_tmp.to_json
      end
    end

    @logger.debug "Baked endpoints"
    @logger.debug " + Final URL: #{final_url}"
    @logger.debug " + Path Params: #{final_path_params}"
    @logger.debug " + Body: #{final_body}"
    @logger.debug " + Headers: #{final_headers}"
    @logger.debug " + Cookies: #{final_cookies}"
    @logger.debug " + Tags: #{final_tags}"

    {
      url:        final_url,
      body:       final_body,
      path_param: final_path_params,
      header:     final_headers,
      cookie:     final_cookies,
      tags:       final_tags.uniq,
      body_type: is_json ? "json" : "form",
    }
  end

  macro define_getter_methods(names)
    {% for name, index in names %}
      def {{name.id}}
        @{{name.id}}
      end
    {% end %}
  end

  define_getter_methods [logger, output_file]
end
