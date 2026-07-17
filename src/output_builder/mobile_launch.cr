require "../models/endpoint"

# Helpers shared by the mobile launch-command builders (adb, simctl). A mobile
# entry point's launcher depends on the platform that declared it: Android
# entry points launch via `adb`, iOS ones via `xcrun simctl`. Each builder
# emits for its own platform and skips the rest, so both need the same origin
# classification and the same "is this actually launchable?" / shell-quoting
# rules — kept here so the two stay in lock-step.
module MobileLaunch
  # An iOS-originated mobile endpoint. The analyzer framework tags each
  # endpoint with its detector tech (`details.technology`): the Android
  # manifest analyzer -> "android", the iOS analyzer -> "ios". The shared App
  # Links analyzer ("well_known_applinks") emits both platforms, told apart by
  # the backing file — Android `assetlinks.json` vs Apple
  # apple-app-site-association.
  def ios_origin?(endpoint : Endpoint) : Bool
    tech = endpoint.details.technology
    return true if tech == "ios"
    return false unless tech == "well_known_applinks"

    # Classify as iOS only on an affirmative Apple apple-app-site-association
    # backing file. The old `none? { assetlinks.json }` was vacuously true for
    # an empty code_paths list (which optimization can produce), so an Android
    # App-Links association with no code_paths leaked into the iOS simctl list.
    endpoint.details.code_paths.any? { |pi| File.basename(pi.path) == "apple-app-site-association" }
  end

  # App Links / Universal Links from `.well-known` files are bare path
  # patterns (`/*`, `/buy/*`) bound to a domain that isn't in the URL, so they
  # can't become a concrete launch. Every real launchable entry point carries
  # a scheme (`myapp://`, `intent://`, `content://`, `https://`, `mailto:`),
  # none of which start with `/`.
  def launchable?(url : String) : Bool
    !url.starts_with?("/")
  end

  def shell_quote(str : String) : String
    "'#{str.gsub("'", "'\\''")}'"
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
    return shell_quote(str) unless str.matches?(DEVICE_SHELL_METACHARS)
    shell_quote(shell_quote(str))
  end

  def plural(count : Int32) : String
    count == 1 ? "" : "s"
  end
end
