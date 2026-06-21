require "colorize"
require "./logger"
require "../utils/utils"
require "../utils/http_symbols"

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
    @proxy = options["probe_via"].to_s
    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log

    options["probe_header"].as_a.each do |set_header|
      raw = set_header.to_s
      # Only split on the first colon so values that contain colons
      # (e.g. `Authorization: Bearer aaa:bbb`, `X-Time: 12:34:56`)
      # keep their full payload after the header name.
      colon_index = raw.index(':')
      if colon_index.nil?
        # Pre-fix this dropped silently. A typo like
        # `--probe-header "X-Auth tok123"` (missing colon) meant the
        # auth never got sent and the user wondered why every probe
        # returned 401.
        STDERR.puts "WARNING: --probe-header value '#{raw}' is missing a ':' — expected 'Name: value' format. Skipping.".colorize(:yellow)
        next
      end

      name = raw[0...colon_index]
      if name.empty?
        STDERR.puts "WARNING: --probe-header value '#{raw}' has an empty header name (nothing before ':'). Skipping.".colorize(:yellow)
        next
      end

      value = raw[(colon_index + 1)..]
      value = value.lstrip(' ') unless value.empty?
      @headers[name] = value
    end

    options["probe_match"].as_a.each do |matcher|
      @matchers << matcher.to_s
    end
    @matchers.delete("")
    unless @matchers.empty?
      @logger.info "#{@matchers.size} matchers added."
    end

    options["probe_skip"].as_a.each do |filter|
      @filters << filter.to_s
    end
    @filters.delete("")
    unless @filters.empty?
      @logger.info "#{@filters.size} filters added."
    end
  end

  def apply_all(endpoints : Array(Endpoint))
    result = endpoints
    @logger.debug "Matchers: #{@matchers}"
    @logger.debug "Filters: #{@filters}"

    unless @matchers.empty?
      @logger.info "Applying matchers"
      result = apply_matchers(result)
    end

    unless @filters.empty?
      @logger.info "Applying filters"
      result = apply_filters(result)
    end

    result
  end

  def apply_matchers(endpoints : Array(Endpoint))
    result = [] of Endpoint
    endpoints.each do |endpoint|
      @matchers.each do |matcher|
        next unless matches_pattern?(endpoint, matcher)
        @logger.debug "Endpoint '#{endpoint.method} #{endpoint.url}' matched with '#{matcher}'."
        result << endpoint
        # Stop after the first matching pattern so an endpoint that
        # satisfies several matchers (e.g. matchers = ["GET", "GET:/api"])
        # isn't emitted twice.
        break
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

      if ALLOWED_HTTP_METHODS.includes?(upper_pattern)
        endpoint.method.upcase == upper_pattern
      else
        # Backward compatibility: check URL
        endpoint.url.includes?(pattern)
      end
    end
  end
end
