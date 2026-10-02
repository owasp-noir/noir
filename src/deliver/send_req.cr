require "../models/deliver"
require "../models/skipped_files"

class SendReq < Deliver
  # Every probe goes out with `handle_errors: false, max_redirects: 0`.
  # The two belong together and neither is optional:
  #
  # `handle_errors` defaults to true in Crest, which raises
  # `Crest::RequestFailed` on any non-2xx. A probe's whole job is to fire
  # the request — a 404 or a 500 is a delivered probe, not a delivery
  # failure. Left on, it fed the `failures` counter below, and since path
  # templates like `/users/{id}` are probed literally, most probes against
  # a real app 404. The "N request(s) failed" line then fired en masse and
  # buried the case it exists for: a genuinely broken target (bad -u, TLS
  # rejection, network down).
  #
  # `max_redirects: 0` must be set alongside it, not alone —
  # `Redirector#check_max_redirects` raises when
  # `max_redirects <= 0 && handle_errors`, so setting it by itself turns
  # every 3xx into a counted failure and makes things worse. Redirects are
  # off because Crest copies the request headers onto the redirected
  # request, including a `--probe-header` Authorization token, and follows
  # absolute Locations to other hosts. Beyond the credential leak,
  # following them generates traffic to URLs noir never discovered, which
  # is not what "replay my endpoints" means.
  def run(endpoints : Array(Endpoint))
    failed = probe_all(endpoints, tls_context, "request delivery")

    # Individual failures stay at debug, but a total count surfaces once so
    # a fully-broken target (bad -u, TLS rejection, network down) isn't
    # mistaken for a clean run. With `handle_errors: false` above this now
    # counts only requests that never completed — a 404/500 response is a
    # delivered probe and no longer lands here.
    return if failed == 0

    @logger.warning "Probe delivery: #{failed} request(s) could not be sent (run with --debug for details)."
    # A probe that never left the machine is delivery the user asked for and
    # did not get, so it belongs in `errors` next to the analyzer gaps rather
    # than in a warning line nobody reads on a green CI run.
    Noir::SkippedFiles.record_gap(
      Noir::SkippedFiles::DELIVER_SCOPE,
      "probe delivery: #{failed} request#{"s" if failed != 1} could not be sent (run with --debug for details)"
    )
  end
end
