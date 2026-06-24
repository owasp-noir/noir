require "../../models/tagger"
require "../../models/endpoint"

# Flags debug, diagnostic, and internal-only endpoints — debug consoles
# and toggles, profilers, Spring Boot Actuator, Go `net/http/pprof`,
# heap/thread dumps, `phpinfo`, and `/internal` APIs. These should not be
# publicly reachable: they leak environment, config, stack traces, and
# heap contents, and some allow unsafe diagnostic actions (shutdown, GC,
# logger changes). Surfacing them points a reviewer at a high-value,
# frequently-misexposed surface.
class DebugTagger < Tagger
  # Unambiguous debug/diagnostic path segments — one is enough. Matched
  # as whole segments after splitting on `/`, `-`, `_`, `.`, so
  # `/__debug__/` and `/debug/pprof` both yield a `debug` token,
  # `phpinfo.php` yields `phpinfo`, and `/actuator/loggers` is covered
  # both by `actuator` and root-path-exposed `/loggers`.
  STRONG_PATH_PARTS = Set{
    "debug", "debugger", "xdebug", "actuator", "pprof", "heapdump",
    "heapdumps", "threaddump", "threaddumps", "phpinfo", "profiler",
    "jolokia", "telescope", "loggers", "configprops",
    "debugbar", "clockwork", "wdt",
  }

  # A debug toggle parameter (`?debug=true`, `?xdebug=...`) flips an
  # endpoint into a debug/verbose mode regardless of its path.
  # `__debugger__` is Werkzeug's interactive-console (RCE) marker.
  # The `xdebug_session*` / `xdebug_profile` triggers (sent as cookie,
  # GET, or POST param) switch Xdebug into remote-debug or profiling mode
  # — a well-known production exposure.
  STRONG_PARAM_NAMES = Set{
    "debug", "xdebug", "debug_mode", "debugger", "__debugger__",
    "xdebug_session", "xdebug_session_start", "xdebug_profile", "xdebug_trigger",
  }

  # `internal` / `_internal` is matched only as a standalone slash
  # segment (not the `-`/`_` split used elsewhere), so `/internal/jobs`
  # is flagged but compound business names like `/internal-transfer`,
  # `/internal-notes`, or `/internalized` are not.
  INTERNAL_SEGMENTS = Set{"internal", "_internal"}

  # Weaker, more generic diagnostic segments. These also name ordinary
  # product features (a "metrics" dashboard, a "console" UI), so tag only
  # when two *distinct* weak tokens co-occur.
  WEAK_PATH_PARTS = Set{
    "metrics", "monitor", "monitoring", "diagnostics", "diagnostic",
    "trace", "traces", "console", "dump", "dumps", "prometheus",
  }

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "debug"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      param_names = endpoint.params.map { |param| normalize_param_name(param.name) }.to_set
      url_segments = url_parts(endpoint.url)

      has_strong = !(STRONG_PARAM_NAMES & param_names).empty? ||
                   url_segments.any? { |part| STRONG_PATH_PARTS.includes?(part) } ||
                   internal_segment?(endpoint.url)

      # Distinct weak path tokens only — a repeated segment
      # (`/monitor/monitor-x`) can't satisfy the threshold by itself.
      weak_tokens = Set(String).new
      url_segments.each do |part|
        weak_tokens << part if WEAK_PATH_PARTS.includes?(part)
      end

      check = has_strong || weak_tokens.size >= 2

      if check
        tag = Tag.new(
          "debug",
          "Debug, diagnostic, or internal-only endpoint (debug consoles/toggles, profilers, actuator/management, pprof, heap/thread dumps, internal APIs); should not be publicly reachable — review for information exposure and unsafe diagnostic actions.",
          "Debug"
        )
        endpoint.add_tag(tag)
      end
    end
  end

  private def url_parts(url : String) : Array(String)
    strip_scheme(url).downcase.split(/[\/\-_\.]+/).reject(&.empty?)
  end

  # Slash/dot-delimited segments only (hyphens and underscores kept
  # inside a segment), so `internal` matches as its own path component
  # but not as part of a compound word.
  private def internal_segment?(url : String) : Bool
    strip_scheme(url).downcase.split(/[\/.]+/).reject(&.empty?).any? { |seg| INTERNAL_SEGMENTS.includes?(seg) }
  end

  # Drop a leading URI scheme (`scheme://`) before tokenizing. Mobile
  # deep-link entry points arrive as custom-scheme URLs whose scheme is the
  # app's reverse-domain bundle id — e.g.
  # `ShareMedia-app.futo.immich.debug.Widget://`, where `debug` is the build
  # *flavor*, not a debug endpoint. Tokenizing the scheme produced a false
  # `debug` match; the authority/path after `://` (the real deep-link
  # target, e.g. `myapp://debug-console`) is kept and still matched.
  private def strip_scheme(url : String) : String
    if idx = url.index("://")
      url[(idx + 3)..]
    else
      url
    end
  end
end
