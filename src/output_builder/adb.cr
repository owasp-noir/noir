require "../models/output_builder"
require "../models/endpoint"

# Emits `adb` (Android Debug Bridge) commands that launch the mobile entry
# points Noir discovers — custom-scheme deep links, verified app links,
# explicit intent components, and content providers — on a connected Android
# device or emulator.
#
# It is the mobile counterpart to the curl/httpie/powershell builders: those
# render HTTP requests and skip mobile endpoints, while this one renders
# mobile launches and skips HTTP endpoints. Because `-f adb` can't express an
# HTTP request, the dropped endpoints are reported once as a warning (to
# STDERR, so the command list on STDOUT stays pipe-clean).
class OutputBuilderAdb < OutputBuilder
  # Default action for a deep-link (scheme / app-link) launch when the
  # intent-filter recorded none — Android registers VIEW for browsable links.
  DEFAULT_ACTION = "android.intent.action.VIEW"

  def print(endpoints : Array(Endpoint))
    skipped = 0
    endpoints.each do |endpoint|
      unless endpoint.mobile?
        skipped += 1
        next
      end

      ob_puts command_for(endpoint)
    end

    warn_about_skipped(skipped)
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

  private def warn_about_skipped(skipped : Int32)
    return if skipped.zero?

    @logger.warning "-f adb: skipped #{skipped} HTTP endpoint#{skipped == 1 ? "" : "s"} — " \
                    "adb launches apply only to mobile entry points " \
                    "(mobile-scheme / universal-link / android-intent / android-provider)."
  end

  private def shell_quote(str : String) : String
    "'#{str.gsub("'", "'\\''")}'"
  end
end
