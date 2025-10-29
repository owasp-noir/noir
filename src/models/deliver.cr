require "./logger"
require "../utils/utils"

class Deliver
  @logger : NoirLogger
  @options : Hash(String, YAML::Any)
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @proxy : String
  @headers : Hash(String, String) = {} of String => String
  @matchers : Array(String) = [] of String
  @filters : Array(String) = [] of String

  def initialize(options : Hash(String, YAML::Any))
    @options = options
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @is_color = any_to_bool(options["color"])
    @is_log = any_to_bool(options["nolog"])
    @proxy = options["send_proxy"].to_s
    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log

    options["send_with_headers"].as_a.each do |set_header|
      if set_header.to_s.includes? ":"
        splited = set_header.to_s.split(":")
        value = ""
        begin
          if splited[1][0].to_s == " "
            value = splited[1][1..-1].to_s
          else
            value = splited[1].to_s
          end
        rescue
          value = splited[1].to_s
        end

        @headers[splited[0]] = value
      end
    end

    options["use_matchers"].as_a.each do |matcher|
      @matchers << matcher.to_s
    end
    @matchers.delete("")
    if !@matchers.empty?
      @logger.info "#{@matchers.size} matchers added."
    end

    options["use_filters"].as_a.each do |filter|
      @filters << filter.to_s
    end
    @filters.delete("")
    if !@filters.empty?
      @logger.info "#{@filters.size} filters added."
    end
  end

  def apply_all(endpoints : Array(Endpoint))
    result = endpoints
    @logger.debug "Matchers: #{@matchers}"
    @logger.debug "Filters: #{@filters}"

    if !@matchers.empty?
      @logger.info "Applying matchers"
      result = apply_matchers(endpoints)
    end

    if !@filters.empty?
      @logger.info "Applying filters"
      result = apply_filters(endpoints)
    end

    result
  end

  def apply_matchers(endpoints : Array(Endpoint))
    result = [] of Endpoint
    endpoints.each do |endpoint|
      @matchers.each do |matcher|
        if matches_pattern?(endpoint, matcher)
          @logger.debug "Endpoint '#{endpoint.method} #{endpoint.url}' matched with '#{matcher}'."
          result << endpoint
        end
      end
    end

    result
  end

  def apply_filters(endpoints : Array(Endpoint))
    result = [] of Endpoint
    endpoints.each do |endpoint|
      should_filter = false
      @filters.each do |filter|
        if matches_pattern?(endpoint, filter)
          @logger.debug "Endpoint '#{endpoint.method} #{endpoint.url}' filtered with '#{filter}'."
          should_filter = true
          break
        end
      end
      unless should_filter
        result << endpoint
      end
    end

    result
  end

  def proxy
    @proxy
  end

  def headers
    @headers
  end

  def matchers
    @matchers
  end

  def filters
    @filters
  end

  def run
    # After inheriting the class, write an action code here.
  end

  private def matches_pattern?(endpoint : Endpoint, pattern : String) : Bool
    # Check if pattern contains method:url format
    if pattern.includes? ":"
      parts = pattern.split(":", 2)
      method_pattern = parts[0].upcase
      url_pattern = parts[1]

      # Check if method matches and URL contains pattern
      endpoint.method.upcase == method_pattern && endpoint.url.includes?(url_pattern)
    else
      # Check if pattern is just a method name
      upper_pattern = pattern.upcase
      http_methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "TRACE", "CONNECT"]

      if http_methods.includes?(upper_pattern)
        endpoint.method.upcase == upper_pattern
      else
        # Backward compatibility: check URL
        endpoint.url.includes?(pattern)
      end
    end
  end
end
