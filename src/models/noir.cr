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
    if options[:debug] == "yes"
      @is_debug = true
    else
      @is_debug = false
    end

    if options[:color] == "yes"
      @is_color = true
    else
      @is_color = false
    end

    @logger = NoirLogger.new @is_debug, @is_color

    if options[:techs].size > 0
      @techs = options[:techs].split(",")
    end
  end

  def run
    puts @techs
  end

  def detect
    detected_techs = detect_techs options[:base]
    @techs += detected_techs
  end

  def analyze
    @endpoints = analysis_endpoints options, @techs
    optimize_endpoints
    deliver()
  end

  def optimize_endpoints
    tmp = [] of Endpoint
    @endpoints.each do |endpoint|
      tiny_tmp = endpoint
      if endpoint.params.size > 0
        tiny_tmp.params = [] of Param
        endpoint.params.each do |param|
          if !param.name.includes? " "
            tiny_tmp.params << param
          end
        end
      end

      if endpoint.url != ""
        tmp << tiny_tmp
      end
    end

    @endpoints = tmp
  end

  def deliver
    if @send_proxy != ""
      send_with_proxy(@endpoints, @send_proxy)
    end

    if @send_req != "no"
      send_req(@endpoints)
    end
  end

  def report
    case options[:format]
    when "json"
      puts @endpoints.to_json
    when "markdown-table"
      puts "| Endpoint | Params |"
      puts "| -------- | ------ |"

      @endpoints.each do |endpoint|
        if !endpoint.params.nil? && @scope.includes?("param")
          params_text = ""
          endpoint.params.each do |param|
            params_text += "`#{param.name} (#{param.param_type})` "
          end
          puts "| #{endpoint.method} #{endpoint.url} | #{params_text} |"
        else
          puts "| #{endpoint.method} #{endpoint.url} | - |"
        end
      end
    when "httpie"
      @endpoints.each do |endpoint|
        cmd = "http #{endpoint.method} #{endpoint.url}"

        if !endpoint.params.nil? && @scope.includes?("param")
          endpoint.params.each do |param|
            cmd += " \"#{param.name}=#{param.value}\""
          end
        end
        puts cmd
      end
    when "curl"
      @endpoints.each do |endpoint|
        cmd = "curl -i -k -X #{endpoint.method} #{endpoint.url}"
        if !endpoint.params.nil? && @scope.includes?("param")
          endpoint.params.each do |param|
            cmd += " -d \"#{param.name}=#{param.value}\""
          end
        end
        puts cmd
      end
    else
      @endpoints.each do |endpoint|
        final_url = endpoint.url
        final_body = ""
        is_json = false
        first_query = true
        first_form = true

        if !endpoint.params.nil? && @scope.includes?("param")
          endpoint.params.each do |param|
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

            if param.param_type == "json"
              is_json = true
            end
          end
        end

        if final_body != ""
          puts "#{endpoint.method} #{final_url}"
          puts final_body
          puts ""
        elsif is_json
          final_json = Hash(String, String).new
          endpoint.params.each do |param|
            if param.param_type == "json"
              final_json[param.name] = param.value
            end
          end

          puts "#{endpoint.method} #{final_url}"
          puts final_json.to_json
          puts ""
        else
          puts "#{endpoint.method} #{final_url}"
        end
      end
    end
  end
end
