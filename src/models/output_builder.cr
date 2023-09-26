require "./logger"

class OutputBuilder
  @logger : NoirLogger
  @options : Hash(Symbol, String)
  @is_debug : Bool
  @is_color : Bool
  @is_log : Bool
  @scope : String
  @output_file : String

  def initialize(options : Hash(Symbol, String))
    @is_debug = str_to_bool(options[:debug])
    @options = options
    @is_color = str_to_bool(options[:color])
    @is_log = str_to_bool(options[:nolog])
    @scope = options[:scope]
    @output_file = options[:output]

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
    if @is_debug
      @logger.debug "Baking endpoint #{url} with #{params.size} params."
    end

    final_url = url
    final_body = ""
    final_headers = [] of String
    is_json = false
    first_query = true
    first_form = true

    if !params.nil? && @scope.includes?("param")
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

        if param.param_type == "header"
          final_headers << "#{param.name}: #{param.value}"
        end

        if param.param_type == "json"
          is_json = true
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

    if @is_debug
      @logger.debug "Baked endpoint #{final_url} with #{final_body} body and #{final_headers.size} headers."
    end

    {
      url:       final_url,
      body:      final_body,
      header:    final_headers,
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

  define_getter_methods [scope, logger]
end
