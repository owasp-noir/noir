require "../models/output_builder"
require "../models/endpoint"
require "./mobile_launch"

# Emits `adb` (Android Debug Bridge) commands that launch the Android entry
# points Noir discovers — custom-scheme deep links, verified app links,
# explicit intent components, and content providers — on a connected Android
# device or emulator.
#
# It is the Android counterpart to the curl/httpie/powershell builders: those
# render HTTP requests and skip mobile endpoints, while this one renders
# Android launches and skips everything `adb` can't express. `adb` is
# Android-only, so iOS-originated entry points are skipped (launch those with
# `xcrun simctl openurl` — a dedicated `-f simctl` format is a follow-up). The
# dropped endpoints are reported once per category as a warning (to STDERR, so
# the command list on STDOUT stays pipe-clean).
class OutputBuilderAdb < OutputBuilder
  include MobileLaunch

  # Default action for a deep-link (scheme / app-link) launch when the
  # intent-filter recorded none — Android registers VIEW for browsable links.
  DEFAULT_ACTION = "android.intent.action.VIEW"

  def print(endpoints : Array(Endpoint))
    skipped_http = 0
    skipped_ios = 0
    skipped_unlaunchable = 0

    endpoints.each do |endpoint|
      unless endpoint.mobile?
        skipped_http += 1
        next
      end
      if ios_origin?(endpoint)
        skipped_ios += 1
        next
      end
      # App Links domain associations are bare path patterns, not launchable.
      unless launchable?(endpoint.url)
        skipped_unlaunchable += 1
        next
      end

      ob_puts command_for(endpoint)
    end

    warn_about_skipped(skipped_http, skipped_ios, skipped_unlaunchable)
  end

  private def command_for(endpoint : Endpoint) : String
    case endpoint.protocol
    when "android-provider"
      provider_command(endpoint)
    when "android-intent"
      intent_command(endpoint)
    else # mobile-scheme / universal-link — deep links opened via VIEW
      deeplink_command(endpoint)
    end
  end

  # `content://authority[/path]` is addressed through a ContentResolver, which
  # the `content` shell tool drives. A read (`query`) is the safe default; a
  # reviewer flips it to insert/update/delete as needed.
  private def provider_command(endpoint : Endpoint) : String
    baked = bake_endpoint(endpoint.url, endpoint.params)
    "adb shell content query --uri #{shell_quote(baked[:url])}"
  end

  # Explicit IPC component (`intent://package/Component`). The `intent://`
  # scheme is synthetic — added so the optimizer leaves the component name
  # alone — so strip it back to the `package/Component` form `am -n` expects,
  # and route activities / services / receivers to the right `am` subcommand.
  private def intent_command(endpoint : Endpoint) : String
    meta = endpoint.metadata || {} of String => String
    component = endpoint.url.lchop("intent://")
    verb = case meta["component_type"]?
           when "service"  then "startservice"
           when "receiver" then "broadcast"
           else                 "start" # activity / activity-alias / unknown
           end

    parts = ["adb", "shell", "am", verb]
    if action = meta["action"]?
      parts << "-a" << shell_quote(action)
    end
    # `-n package/Component` names the explicit target. A component-less
    # `intent://package` can't be named, so fall back to limiting the launch
    # to the package (`-p`).
    if component.includes?('/')
      parts << "-n" << shell_quote(component)
    else
      parts << "-p" << shell_quote(component)
    end
    append_categories(parts, meta)
    append_extras(parts, endpoint)
    parts.join(" ")
  end

  # Custom-scheme deep link (`myapp://host/path`) or verified app link
  # (`https://host/path`) — both are opened with an implicit VIEW intent.
  private def deeplink_command(endpoint : Endpoint) : String
    meta = endpoint.metadata || {} of String => String
    baked = bake_endpoint(endpoint.url, endpoint.params)
    action = meta["action"]? || DEFAULT_ACTION

    parts = ["adb", "shell", "am", "start", "-a", shell_quote(action)]
    append_categories(parts, meta)
    parts << "-d" << shell_quote(baked[:url])
    # Constrain the launch to the declaring app when it's known, so the link
    # isn't grabbed by another handler or the disambiguation chooser.
    if package = meta["package"]?
      parts << "-p" << shell_quote(package) unless package.empty?
    end
    append_extras(parts, endpoint)
    parts.join(" ")
  end

  # The intent-filter records at most one category in metadata; pass it through
  # as `-c` so a launch that needs e.g. BROWSABLE matches the declared filter.
  private def append_categories(parts : Array(String), meta : Hash(String, String))
    if category = meta["category"]?
      parts << "-c" << shell_quote(category) unless category.empty?
    end
  end

  # Intent extras (Bundle inputs, `param_type == "extra"`) a handler reads.
  # Emit them as string extras (`--es name value`) so the launch carries the
  # same keys the code expects; values stay empty templates unless seeded with
  # `--pvalue`.
  private def append_extras(parts : Array(String), endpoint : Endpoint)
    endpoint.params.each do |param|
      next unless param.param_type == "extra"
      parts << "--es" << shell_quote(param.name) << shell_quote(param.value)
    end
  end

  private def warn_about_skipped(http : Int32, ios : Int32, unlaunchable : Int32)
    unless http.zero?
      @logger.warning "-f adb: skipped #{http} HTTP endpoint#{plural(http)} — " \
                      "adb launches apply only to Android entry points " \
                      "(mobile-scheme / universal-link / android-intent / android-provider)."
    end
    unless ios.zero?
      @logger.warning "-f adb: skipped #{ios} iOS entry point#{plural(ios)} — " \
                      "adb is Android-only; launch iOS schemes with `xcrun simctl openurl`."
    end
    unless unlaunchable.zero?
      @logger.warning "-f adb: skipped #{unlaunchable} App Links domain association#{plural(unlaunchable)} — " \
                      "these declare a verified domain, not a concrete URL to launch."
    end
  end
end
