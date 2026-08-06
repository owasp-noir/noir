require "colorize"
require "openssl"
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

  # Requests that never completed during the last `run` — connection
  # refused, TLS handshake rejected, DNS failure, timeout. Deliberately
  # *not* incremented for an HTTP error response: a 404 or 500 means the
  # probe was delivered and answered. Exposed so the distinction is
  # assertable, since the count is otherwise only visible as a log line.
  getter undeliverable_count : Int32 = 0

  protected def undeliverable_count=(count : Int32)
    @undeliverable_count = count
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

  # Max concurrent in-flight probe requests. Bounds the fiber/socket fan-out
  # so a large endpoint set can't exhaust file descriptors. Backed by the
  # validated --concurrency value (already clamped to a sane ceiling).
  protected def concurrency_limit : Int32
    n = @options["concurrency"]?.try(&.to_s.to_i?) || 0
    n > 0 ? n : 16
  end

  # TLS context for outbound delivery. Verifying (secure) by default; the
  # old behaviour skipped verification unconditionally, silently exposing
  # the endpoint catalog to MITM on the way to a webhook / Elasticsearch.
  # `--tls-skip-verify` restores the insecure context for self-signed
  # internal endpoints.
  protected def tls_context : OpenSSL::SSL::Context::Client
    if any_to_bool(@options["tls_skip_verify"]?)
      OpenSSL::SSL::Context::Client.insecure
    else
      OpenSSL::SSL::Context::Client.new
    end
  end

  # A `METHOD:url` pattern is only method-scoped when the token before the
  # first colon really is a verb an endpoint can carry. Splitting on *any*
  # colon read `--probe-skip https://api.example.com/admin` as method
  # `HTTPS` + url `//api.example.com/admin`, which matches nothing — so the
  # filter silently did nothing and every endpoint the user meant to skip
  # was probed anyway. That is the common shape, not an edge case: every
  # delivery target requires `-u`, which rewrites each endpoint to
  # `scheme://host/path`, so pasting a full URL into --probe-match /
  # --probe-skip is the natural thing to do. A `host:8080/x` pattern hit the
  # same hole.
  private def matches_pattern?(endpoint : Endpoint, pattern : String) : Bool
    colon_index = pattern.index(':')
    if colon_index && endpoint_method_token?(pattern[0...colon_index])
      method_pattern = pattern[0...colon_index].upcase
      url_pattern = pattern[(colon_index + 1)..]

      # Check if method matches and URL contains pattern
      return endpoint.method.upcase == method_pattern && endpoint.url.includes?(url_pattern)
    end

    # Pattern is just a method name. Matched against every verb an endpoint
    # can carry (not only the real HTTP ones) so `--probe-skip SEND` and
    # `--probe-skip CLI` filter the same way `SEND:/ws` does.
    if endpoint_method_token?(pattern)
      endpoint.method.upcase == pattern.upcase
    else
      # Backward compatibility: check URL
      endpoint.url.includes?(pattern)
    end
  end
end
