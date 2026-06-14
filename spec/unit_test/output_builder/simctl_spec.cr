require "../../spec_helper"
require "../../../src/output_builder/simctl"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

private def build_simctl_builder
  options = {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
    "output"  => YAML::Any.new(""),
  }
  builder = OutputBuilderSimctl.new(options)
  builder.io = IO::Memory.new
  builder
end

# The simctl builder is the iOS counterpart to the adb builder: it renders
# `xcrun simctl openurl` launches for iOS entry points and skips everything
# `simctl` can't open (HTTP, Android, bare App Links associations).
describe "OutputBuilderSimctl" do
  it "renders an iOS custom-scheme deep link as an openurl launch" do
    scheme = Endpoint.new("myapp://host/path", "GET")
    scheme.protocol = "mobile-scheme"
    scheme.details.technology = "ios"

    builder = build_simctl_builder
    builder.print([scheme])
    out = builder.io.to_s.strip

    out.should eq("xcrun simctl openurl booted 'myapp://host/path'")
  end

  it "bakes query params into the launched URL" do
    scheme = Endpoint.new("myapp://open", "GET")
    scheme.protocol = "mobile-scheme"
    scheme.details.technology = "ios"
    scheme.push_param(Param.new("redirect", "", "query"))
    scheme.push_param(Param.new("token", "", "query"))

    builder = build_simctl_builder
    builder.print([scheme])
    out = builder.io.to_s.strip

    out.should eq("xcrun simctl openurl booted 'myapp://open?redirect=&token='")
  end

  it "renders an iOS universal link as an openurl launch" do
    applink = Endpoint.new("https://app.example.com/buy", "GET")
    applink.protocol = "universal-link"
    applink.details.technology = "ios"

    builder = build_simctl_builder
    builder.print([applink])
    out = builder.io.to_s.strip

    out.should eq("xcrun simctl openurl booted 'https://app.example.com/buy'")
  end

  it "skips HTTP endpoints and only emits iOS launches" do
    http = Endpoint.new("/api/users", "GET")
    scheme = Endpoint.new("myapp://host/path", "GET")
    scheme.protocol = "mobile-scheme"
    scheme.details.technology = "ios"

    builder = build_simctl_builder
    builder.print([http, scheme])
    out = builder.io.to_s

    out.should_not contain("/api/users")
    out.should contain("myapp://host/path")
  end

  it "skips Android-originated entry points (simctl is iOS-only)" do
    android = Endpoint.new("myandroidapp://open", "GET")
    android.protocol = "mobile-scheme"
    android.details.technology = "android"
    intent = Endpoint.new("intent://com.example.app/.FooActivity", "GET")
    intent.protocol = "android-intent"
    intent.details.technology = "android"
    ios = Endpoint.new("myapp://host/path", "GET")
    ios.protocol = "mobile-scheme"
    ios.details.technology = "ios"

    builder = build_simctl_builder
    builder.print([android, intent, ios])
    out = builder.io.to_s

    out.should_not contain("myandroidapp://open")
    out.should_not contain("intent://")
    out.should contain("myapp://host/path")
  end

  it "classifies well_known App Links by their backing file and skips the bare path" do
    # An Apple AASA association and an Android assetlinks.json association both
    # surface as bare `/*` universal links under the well_known_applinks tech;
    # neither has a launchable scheme.
    ios_link = Endpoint.new("/buy/*", "GET", Details.new(PathInfo.new("app/apple-app-site-association")))
    ios_link.protocol = "universal-link"
    ios_link.details.technology = "well_known_applinks"

    android_link = Endpoint.new("/*", "GET", Details.new(PathInfo.new("app/.well-known/assetlinks.json")))
    android_link.protocol = "universal-link"
    android_link.details.technology = "well_known_applinks"

    builder = build_simctl_builder
    builder.print([ios_link, android_link])
    out = builder.io.to_s.strip

    out.should be_empty
  end
end
