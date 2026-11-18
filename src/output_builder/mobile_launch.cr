require "../models/endpoint"
require "../utils/control_chars"

# Helpers shared by the mobile launch-command builders (adb, simctl). A mobile
# entry point's launcher depends on the platform that declared it: Android
# entry points launch via `adb`, iOS ones via `xcrun simctl`. Each builder
# emits for its own platform and skips the rest, so both need the same origin
# classification and the same "is this actually launchable?" / shell-quoting
# rules — kept here so the two stay in lock-step.
module MobileLaunch
  def ios_origin?(endpoint : Endpoint) : Bool
    declared_by?(endpoint, "ios")
  end

  def declared_by?(endpoint : Endpoint, platform : String) : Bool
    details = endpoint.details
    return details.origins.any? { |origin| origin.platform == platform } unless details.origins.empty?

    technologies = details.contributing_technologies
    return true if technologies.includes?(platform)
    return false unless technologies.includes?("well_known_applinks")

    details.code_paths.any? do |location|
      name = File.basename(location.path)
      platform == "ios" ? name.in?("apple-app-site-association", "apple-app-site-association.json") : name == "assetlinks.json"
    end
  end

  # App Links / Universal Links from `.well-known` files are bare path
  # patterns (`/*`, `/buy/*`) bound to a domain that isn't in the URL, so they
  # can't become a concrete launch. Every real launchable entry point carries
  # a scheme (`myapp://`, `intent://`, `content://`, `https://`, `mailto:`),
  # none of which start with `/`.
  def launchable?(url : String) : Bool
    !url.starts_with?("/")
  end

  # Control characters become `\xNN` text (`ControlChars`) so a manifest
  # carrying `\e]8;;…` cannot drive the terminal the command is printed to.
  # Lossy: control chars become literal `\xNN` text in the command, not the
  # original bytes (no ANSI-C `$'…'` quoting).
  def shell_quote(str : String) : String
    "'#{ControlChars.escape(str).gsub("'", "'\\''")}'"
  end

  # Characters the on-device shell would interpret (word-splitting, control
  # operators, globs, expansions). `&` is the important one: an OAuth-style
  # deep link `myapp://cb?code=x&state=y` otherwise backgrounds at `&`.
  DEVICE_SHELL_METACHARS = /[\s&;|<>()$`"'\\*?\[\]{}#!~]/

  # `adb shell ARGS...` runs ARGS through a SECOND shell on the device: the
  # host shell strips one quote layer, leaving raw metacharacters exposed to
  # the device shell. When a value carries such a character, quote twice so
  # both shells strip a layer and the device receives the literal value.
  # Metachar-free values (the common case) keep a single clean quote layer.
  def device_shell_quote(str : String) : String
    # Escaped first: the `\` that escaping adds is itself a device metachar.
    str = ControlChars.escape(str)
    return shell_quote(str) unless str.empty? || str.matches?(DEVICE_SHELL_METACHARS)
    shell_quote(shell_quote(str))
  end

  def plural(count : Int32) : String
    count == 1 ? "" : "s"
  end
end
