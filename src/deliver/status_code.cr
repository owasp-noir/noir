require "../models/deliver"
require "../models/endpoint"
require "../models/logger"
require "../utils/http_symbols"
require "../utils/utils"
require "crest"
require "wait_group"

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
  include ProbeConcurrency

  @options : Hash(String, YAML::Any)
  @logger : NoirLogger

  def initialize(@options : Hash(String, YAML::Any), @logger : NoirLogger)
  end

  def apply(endpoints : Array(Endpoint)) : Array(Endpoint)
    @logger.sub "➔ Updating status codes."

    excluded = excluded_codes
    # One slot per input endpoint, filled in place and compacted at the end,
    # so probing concurrently does not reorder the catalog the user reads.
    #
    # Pre-fix this loop was strictly sequential and unbounded: against a host
    # that drops SYNs, every endpoint waited out its own connect timeout one
    # after another, so a few hundred endpoints stalled the scan for hours
    # before any report was written. SendReq / SendWithProxy already bound
    # their fan-out with --concurrency; the status probe is bounded the same
    # way rather than with a second, differently-shaped mechanism.
    slots = Array(Endpoint?).new(endpoints.size, nil)
    wg = WaitGroup.new
    sem = Channel(Nil).new(concurrency_limit)

    endpoints.each_with_index do |endpoint, index|
      # Mobile deep links (`myapp://`, `intent://`, `content://`), CLI
      # command surfaces (`cli://`) and realtime `ws://` event surfaces are
      # not HTTP requests — the same guard SendReq / SendWithProxy already
      # apply before probing. Without it every one of them was handed to
      # Crest, which raised "Unsupported scheme" per endpoint: a mobile scan
      # with --status-codes printed dozens of `Failed to get status code`
      # errors for endpoints that can never have one.
      if endpoint.non_http?
        slots[index] = endpoint
        next
      end

      request_method = requestable_http_methods(endpoint.method).first?
      unless request_method
        slots[index] = endpoint
        next
      end

      # Copied into a fresh local: `request_method` is reassigned on every
      # iteration, so a fiber closing over it would race the next endpoint's
      # value (and lose the nil-check narrowing besides).
      probe_method = request_method
      wg.add(1)
      sem.send(nil) # acquire a slot (blocks once `concurrency_limit` are in flight)
      spawn do
        begin
          response = request_for(endpoint, probe_method)
          endpoint.details.status_code = response.status_code
          slots[index] = endpoint unless excluded.includes?(response.status_code)
        rescue e
          @logger.error "Failed to get status code for #{endpoint.url} (#{e.message})."
          slots[index] = endpoint
        ensure
          sem.receive # release the slot
          wg.done
        end
      end
    end

    wg.wait
    slots.compact
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

    # `handle_errors: false, max_redirects: 0` — the same pair SendReq and
    # SendWithProxy send, and for the same reasons.
    #
    # `handle_errors` defaults to true in Crest, which raises on any non-2xx.
    # A probe that answered 404 or 500 has answered; that is the code to
    # report, not an exception.
    #
    # `max_redirects` defaults to 10, and `Redirector#follow` only stops at
    # `max_redirects <= 0`, so the probe used to follow `Location`
    # transparently. Three things were wrong with that: the reported
    # `status_code` was the redirect *target's* (302 /redirect -> 200 /final
    # was reported as 200), `--exclude-codes 302` could never match because
    # the 302 was never seen, and an absolute cross-host `Location` let the
    # scanned app steer noir's probes at a third party the user never named.
    # The target of a probe is what the user asked for, not what the server
    # says.
    #
    # The two must travel together: `Redirector#check_max_redirects` raises
    # when `max_redirects <= 0 && handle_errors`, so turning redirects off on
    # its own would make every 3xx a rescued "Failed to get status code" line.
    Crest::Request.execute(
      method: method,
      url: url,
      tls: tls,
      user_agent: "Noir/#{Noir::VERSION}",
      params: params,
      form: form,
      json: json,
      handle_errors: false,
      max_redirects: 0,
      connect_timeout: connect_timeout,
      read_timeout: read_timeout
    )
  end

  # Crest defaults `connect_timeout` to nil, i.e. no timeout at all, so a host
  # that drops SYNs fell back to the OS TCP timeout — around 75 seconds, per
  # endpoint. `Deliver::PROBE_CONNECT_TIMEOUT` is the value the senders
  # already settled on for exactly this; reused rather than duplicated.
  #
  # The read timeout stays at the status probe's own 5s. A status probe only
  # needs the response line, so it can be stricter than a delivery probe,
  # whose job is to hand a slow-but-working target its full request.
  #
  # Both are accessors so a spec can subclass with sub-second values and still
  # exercise the real plumbing into Crest.
  protected def connect_timeout : Time::Span
    Deliver::PROBE_CONNECT_TIMEOUT
  end

  protected def read_timeout : Time::Span
    5.seconds
  end
end
