require "../models/endpoint"
require "../models/logger"
require "../utils/http_symbols"
require "../utils/utils"
require "crest"

# Fills in `details.status_code` for every endpoint (`--status-codes`) and
# drops the ones whose code the user excluded (`--exclude-codes`).
#
# Deliberately not a `Deliver` subclass, even though it is the other thing in
# noir that fires HTTP requests at discovered endpoints. A status probe runs
# before delivery, ignores `--probe-match` / `--probe-skip`, and sends none of
# the `--probe-header` values — it exists to answer "does this route respond,
# and with what", not to replay traffic. Inheriting the sender base would
# quietly give it all three.
class StatusCodeProbe
  @options : Hash(String, YAML::Any)
  @logger : NoirLogger

  def initialize(@options : Hash(String, YAML::Any), @logger : NoirLogger)
  end

  def apply(endpoints : Array(Endpoint)) : Array(Endpoint)
    @logger.sub "➔ Updating status codes."

    excluded = excluded_codes
    final = [] of Endpoint

    endpoints.each do |endpoint|
      # Mobile deep links (`myapp://`, `intent://`, `content://`), CLI
      # command surfaces (`cli://`) and realtime `ws://` event surfaces are
      # not HTTP requests — the same guard SendReq / SendWithProxy already
      # apply before probing. Without it every one of them was handed to
      # Crest, which raised "Unsupported scheme" per endpoint: a mobile scan
      # with --status-codes printed dozens of `Failed to get status code`
      # errors for endpoints that can never have one.
      if endpoint.non_http?
        final << endpoint
        next
      end

      request_method = requestable_http_methods(endpoint.method).first?
      unless request_method
        final << endpoint
        next
      end

      begin
        response = request_for(endpoint, request_method)
        endpoint.details.status_code = response.status_code
        final << endpoint unless excluded.includes?(response.status_code)
      rescue e
        @logger.error "Failed to get status code for #{endpoint.url} (#{e.message})."
        final << endpoint
      end
    end

    final
  end

  private def request_for(endpoint : Endpoint, request_method : String)
    return perform_request(get_symbol(request_method), endpoint.url) if endpoint.params.empty?

    endpoint_hash = endpoint.params_to_hash
    is_json = !endpoint_hash["json"].empty?
    body = is_json ? endpoint_hash["json"] : endpoint_hash["form"]

    perform_request(
      get_symbol(request_method),
      endpoint.url,
      endpoint_hash["query"],
      body,
      is_json
    )
  end

  # A Set dedupes repeated codes (--exclude-codes 404,404,500) for free and
  # gives O(1) membership; empty tokens (a trailing comma) are skipped.
  private def excluded_codes : Set(Int32)
    codes = Set(Int32).new
    raw = @options["exclude_codes"]?.to_s
    return codes if raw.empty?

    raw.split(",").each do |code|
      stripped = code.strip
      next if stripped.empty?
      codes << stripped.to_i
    end
    codes
  end

  # The single point where a request leaves the process, so specs can drive
  # `apply` against canned responses by overriding this one method.
  def perform_request(method, url, params = {} of String => String, form = {} of String => String, json = false)
    # Verify TLS by default; --tls-skip-verify opts into the insecure
    # context for self-signed internal hosts (see Deliver#tls_context).
    tls = if any_to_bool(@options["tls_skip_verify"]?)
            OpenSSL::SSL::Context::Client.insecure
          else
            OpenSSL::SSL::Context::Client.new
          end

    Crest::Request.execute(
      method: method,
      url: url,
      tls: tls,
      user_agent: "Noir/#{Noir::VERSION}",
      params: params,
      form: form,
      json: json,
      handle_errors: false,
      read_timeout: 5.second
    )
  end
end
