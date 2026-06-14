require "../models/output_builder"
require "../models/endpoint"
require "./mobile_launch"

# Emits `xcrun simctl openurl` commands that open the iOS entry points Noir
# discovers — custom-scheme deep links and verified universal links — on a
# booted iOS Simulator.
#
# It is the iOS counterpart to the adb builder: `simctl` is iOS-only, so it
# emits commands for iOS-originated entry points and skips what it can't open —
# HTTP endpoints, Android entry points (use `-f adb`), and bare App Links
# domain associations. iOS has no intent/provider analog, so every emitted
# command is a single `openurl`. Skips are reported per category as a warning
# to STDERR, so the command list on STDOUT stays pipe-clean.
class OutputBuilderSimctl < OutputBuilder
  include MobileLaunch

  def print(endpoints : Array(Endpoint))
    skipped_http = 0
    skipped_android = 0
    skipped_unlaunchable = 0

    endpoints.each do |endpoint|
      unless endpoint.mobile?
        skipped_http += 1
        next
      end
      unless ios_origin?(endpoint)
        skipped_android += 1
        next
      end
      # App Links domain associations are bare path patterns, not launchable.
      unless launchable?(endpoint.url)
        skipped_unlaunchable += 1
        next
      end

      baked = bake_endpoint(endpoint.url, endpoint.params)
      ob_puts "xcrun simctl openurl booted #{shell_quote(baked[:url])}"
    end

    warn_about_skipped(skipped_http, skipped_android, skipped_unlaunchable)
  end

  private def warn_about_skipped(http : Int32, android : Int32, unlaunchable : Int32)
    unless http.zero?
      @logger.warning "-f simctl: skipped #{http} HTTP endpoint#{plural(http)} — " \
                      "simctl opens only iOS entry points (mobile-scheme / universal-link)."
    end
    unless android.zero?
      @logger.warning "-f simctl: skipped #{android} Android entry point#{plural(android)} — " \
                      "simctl is iOS-only; launch Android entry points with `-f adb`."
    end
    unless unlaunchable.zero?
      @logger.warning "-f simctl: skipped #{unlaunchable} App Links domain association#{plural(unlaunchable)} — " \
                      "these declare a verified domain, not a concrete URL to open."
    end
  end
end
