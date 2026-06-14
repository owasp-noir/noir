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

    # Apple App Site Association entry unless an Android Digital Asset Links
    # file backs it.
    endpoint.details.code_paths.none? { |pi| File.basename(pi.path) == "assetlinks.json" }
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

  def plural(count : Int32) : String
    count == 1 ? "" : "s"
  end
end
