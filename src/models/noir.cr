require "../detector/detector.cr"
require "../analyzer/analyzer.cr"
require "./endpoint.cr"
require "./logger.cr"
require "json"

class NoirRunner
  @options : Hash(Symbol, String)
  @techs : Array(String)
  @endpoints : Array(Endpoint)
  @logger : NoirLogger
  @proxy : String
  @scope : String

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
    @proxy = options[:proxy]
    @scope = options[:scope]

    if options[:debug] == "yes"
      @logger = NoirLogger.new true
    else
      @logger = NoirLogger.new false
    end

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

  def send_with_proxy
    if !@proxy.nil?
      @endpoints.each do |_|
        # TODO: send to proxy
      end
    end
  end
end
