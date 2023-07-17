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
    deliver()
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
        puts "#{endpoint.method} #{endpoint.url}"
        if !endpoint.params.nil? && @scope.includes?("param")
          endpoint.params.each do |param|
            puts " - #{param.name} (#{param.param_type})"
          end
        end
      end
    end
  end
end
