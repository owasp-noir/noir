require "../detector/detector.cr"
require "../analysis/analysis.cr"
require "./endpoint.cr"
require "./logger.cr"
require "json"

class NoirRunner
  @options : Hash(Symbol, String)
  @techs : Array(String)
  @endpoints : Array(Endpoint)
  @logger : NoirLogger
  @proxy : String

  def initialize(options)
    @options = options
    @techs = [] of String
    @endpoints = [] of Endpoint
    @proxy = options[:proxy]

    if options[:debug] == "yes"
      @logger = NoirLogger.new true
    else
      @logger = NoirLogger.new false
    end

    if options[:techs].size > 0
      @techs = options[:techs].split(",")
    end
  end

  def options
    @options
  end

  def techs
    @techs
  end

  def endpoints
    @endpoints
  end

  def logger
    @logger
  end

  def run
    puts @techs
  end

  def detect
    @techs = detect_tech options[:base]
  end

  def analyze
    @endpoints = analysis_endpoints options, @techs
  end

  def report
    case options[:format]
    when "json"
      puts @endpoints.to_json
    when "httpie"
      @endpoints.each do |endpoint|
        cmd = "http #{endpoint.method} #{endpoint.url}"

        if !endpoint.params.nil?
          endpoint.params.each do |param|
            cmd += " \"#{param.name}=#{param.value}\""
          end
        end
        puts cmd
      end
    when "curl"
      @endpoints.each do |endpoint|
        cmd = "curl -i -k -X #{endpoint.method} #{endpoint.url}"
        if !endpoint.params.nil?
          endpoint.params.each do |param|
            cmd += " -d \"#{param.name}=#{param.value}\""
          end
        end
        puts cmd
      end
    else
      @endpoints.each do |endpoint|
        puts "#{endpoint.method} #{endpoint.url}"
        if !endpoint.params.nil?
          endpoint.params.each do |param|
            puts " - #{param.name} (#{param.param_type})"
          end
        end
      end
    end
  end

  def send_proxy
    if !@proxy.nil?
      @endpoints.each do |_|
        # TODO: send to proxy
      end
    end
  end
end
