require "../detector/detector.cr"
require "../analyzer/analyzer.cr"
require "../deliver/*"
require "./endpoint.cr"
require "./logger.cr"
require "json"

class NoirRunner
  @options : Hash(Symbol, String)
  @techs : Array(String)
  @endpoints : Array(Endpoint)
  @logger : NoirLogger
  @scope : String
  @send_proxy : String
  @send_req : String
  @is_debug : Bool
  @is_color : Bool
  @is_log : Bool

  macro define_getter_methods(names)
    {% for name, index in names %}
      def {{name.id}}
        @{{name.id}}
      end
    {% end %}
  end

  define_getter_methods [options, techs, endpoints, logger]

  def initialize(options)
    @options = options
    @techs = [] of String
    @endpoints = [] of Endpoint
    @send_proxy = options[:send_proxy]
    @send_req = options[:send_req]
    @scope = options[:scope]
    @is_debug = str_to_bool(options[:debug])
    @is_color = str_to_bool(options[:color])
    @is_log = str_to_bool(options[:nolog])

    @logger = NoirLogger.new @is_debug, @is_color, @is_log

    if options[:techs].size > 0
      techs_tmp = options[:techs].split(",")
      @logger.system "Setting #{techs_tmp.size} techs from command line."
      techs_tmp.each do |tech|
        @techs << NoirTechs.similar_to_tech(tech)
        @logger.debug "Added #{tech} to techs."
      end
    end
  end

  def run
    puts @techs
  end

  def detect
    detected_techs = detect_techs options[:base], options
    @techs += detected_techs
  end

  def analyze
    @endpoints = analysis_endpoints options, @techs, @logger
    optimize_endpoints
    deliver()
  end

  def optimize_endpoints
    @logger.system "Optimizing endpoints."
    tmp = [] of Endpoint
    duplicate = [] of String

    @endpoints.each do |endpoint|
      tiny_tmp = endpoint
      if endpoint.params.size > 0
        tiny_tmp.params = [] of Param
        endpoint.params.each do |param|
          if !param.name.includes? " "
            if @options[:set_pvalue] != ""
              param.value = @options[:set_pvalue]
            end
            tiny_tmp.params << param
          end
        end
      end

      if endpoint.url != "" && !duplicate.includes?(endpoint.method + endpoint.url)
        tmp << tiny_tmp
        duplicate << endpoint.method + endpoint.url
      end
    end

    @endpoints = tmp
  end

  def deliver
    if @send_proxy != ""
      @logger.system "Sending requests with proxy #{@send_proxy}"
      send_with_proxy(@endpoints, @send_proxy)
    end

    if @send_req != "no"
      @logger.system "Sending requests without proxy"
      send_req(@endpoints)
    end
  end

  def bake_endpoint(url : String, params : Array(Param))
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

        if param.param_type == "body"
          if first_form
            final_body += "#{param.name}=#{param.value}"
            first_form
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

    {
      url:       final_url,
      body:      final_body,
      header:    final_headers,
      body_type: is_json ? "json" : "form",
    }
  end

  def report
    case options[:format]
    when "json"
      puts @endpoints.to_json
    when "markdown-table"
      puts "| Endpoint | Protocol | Params |"
      puts "| -------- | -------- | ------ |"

      @endpoints.each do |endpoint|
        if !endpoint.params.nil? && @scope.includes?("param")
          params_text = ""
          endpoint.params.each do |param|
            params_text += "`#{param.name} (#{param.param_type})` "
          end
          puts "| #{endpoint.method} #{endpoint.url} | #{endpoint.protocol} | #{params_text} |"
        else
          puts "| #{endpoint.method} #{endpoint.url} | #{endpoint.protocol} | - |"
        end
      end
    when "httpie"
      @endpoints.each do |endpoint|
        baked = bake_endpoint(endpoint.url, endpoint.params)

        cmd = "http #{endpoint.method} #{baked[:url]}"
        if baked[:body] != ""
          cmd += " #{baked[:body]}"
          if baked[:body_type] == "json"
            cmd += " \"Content-Type:application/json\""
          end
          baked[:header].each do |header|
            cmd += " \"#{header}\""
          end
        end

        puts cmd
      end
    when "curl"
      @endpoints.each do |endpoint|
        baked = bake_endpoint(endpoint.url, endpoint.params)

        cmd = "curl -i -X #{endpoint.method} #{baked[:url]}"
        if baked[:body] != ""
          cmd += " -d \"#{baked[:body]}\""
          if baked[:body_type] == "json"
            cmd += " -H \"Content-Type:application/json\""
          end
          
          baked[:header].each do |header|
            cmd += " -H \"#{header}\""
          end
        end

        puts cmd
      end
    else
      @endpoints.each do |endpoint|
        baked = bake_endpoint(endpoint.url, endpoint.params)

        r_method = endpoint.method.colorize(:light_blue).toggle(@is_color)
        r_url = baked[:url].colorize(:light_yellow).toggle(@is_color)
        r_headers = baked[:header].join(" ").colorize(:light_green).toggle(@is_color)

        r_ws = ""
        if endpoint.protocol == "ws"
          r_ws = "[WEBSOCKET]".colorize(:light_red).toggle(@is_color)
        end

        if baked[:body] != ""
          r_body = baked[:body].colorize(:cyan).toggle(@is_color)
          puts "#{r_method} #{r_url} #{r_body} #{r_headers} #{r_ws}"
        else
          puts "#{r_method} #{r_url} #{r_headers} #{r_ws}"
        end
      end
    end
  end
end
