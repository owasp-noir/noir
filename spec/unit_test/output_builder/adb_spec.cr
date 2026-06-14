require "../../spec_helper"
require "../../../src/output_builder/adb"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

private def build_adb_builder
  options = {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
    "output"  => YAML::Any.new(""),
  }
  builder = OutputBuilderAdb.new(options)
  builder.io = IO::Memory.new
  builder
end

# The adb builder is the mobile mirror of the curl/httpie/powershell builders:
# it renders Android Debug Bridge launches for the mobile entry points Noir
# discovers and skips HTTP endpoints (which `-f adb` can't express).
describe "OutputBuilderAdb" do
  it "renders a custom-scheme deep link as a VIEW launch" do
    scheme = Endpoint.new("myapp://host/path", "GET")
    scheme.protocol = "mobile-scheme"

    builder = build_adb_builder
    builder.print([scheme])
    out = builder.io.to_s.strip

    out.should eq("adb shell am start -a 'android.intent.action.VIEW' -d 'myapp://host/path'")
  end

  it "uses the filter's action/category and constrains to the package" do
    scheme = Endpoint.new("myapp://host/path", "GET")
    scheme.protocol = "mobile-scheme"
    scheme.metadata = {
      "action"   => "android.intent.action.VIEW",
      "category" => "android.intent.category.BROWSABLE",
      "package"  => "com.example.app",
    }

    builder = build_adb_builder
    builder.print([scheme])
    out = builder.io.to_s.strip

    out.should eq("adb shell am start -a 'android.intent.action.VIEW' " \
                  "-c 'android.intent.category.BROWSABLE' -d 'myapp://host/path' -p 'com.example.app'")
  end

  it "renders a verified app link (universal-link) as a VIEW launch" do
    applink = Endpoint.new("https://app.example.com/", "GET")
    applink.protocol = "universal-link"

    builder = build_adb_builder
    builder.print([applink])
    out = builder.io.to_s.strip

    out.should eq("adb shell am start -a 'android.intent.action.VIEW' -d 'https://app.example.com/'")
  end

  it "renders an explicit activity intent with -n" do
    intent = Endpoint.new("intent://com.example.app/.FooActivity", "GET")
    intent.protocol = "android-intent"
    intent.metadata = {"component_type" => "activity"}

    builder = build_adb_builder
    builder.print([intent])
    out = builder.io.to_s.strip

    out.should eq("adb shell am start -n 'com.example.app/.FooActivity'")
  end

  it "routes services and receivers to the right am subcommand" do
    service = Endpoint.new("intent://com.example.app/.SyncService", "GET")
    service.protocol = "android-intent"
    service.metadata = {"component_type" => "service", "action" => "com.example.SYNC"}

    receiver = Endpoint.new("intent://com.example.app/.BootReceiver", "GET")
    receiver.protocol = "android-intent"
    receiver.metadata = {"component_type" => "receiver"}

    builder = build_adb_builder
    builder.print([service, receiver])
    lines = builder.io.to_s.split("\n").reject(&.empty?)

    lines[0].should eq("adb shell am startservice -a 'com.example.SYNC' -n 'com.example.app/.SyncService'")
    lines[1].should eq("adb shell am broadcast -n 'com.example.app/.BootReceiver'")
  end

  it "renders a content provider as a content query" do
    provider = Endpoint.new("content://com.example.app.provider", "GET")
    provider.protocol = "android-provider"

    builder = build_adb_builder
    builder.print([provider])
    out = builder.io.to_s.strip

    out.should eq("adb shell content query --uri 'content://com.example.app.provider'")
  end

  it "passes intent extras as string extras" do
    intent = Endpoint.new("intent://com.example.app/.FooActivity", "GET")
    intent.protocol = "android-intent"
    intent.metadata = {"component_type" => "activity"}
    intent.push_param(Param.new("token", "", "extra"))

    builder = build_adb_builder
    builder.print([intent])
    out = builder.io.to_s.strip

    out.should eq("adb shell am start -n 'com.example.app/.FooActivity' --es 'token' ''")
  end

  it "skips HTTP endpoints and only emits Android launches" do
    http = Endpoint.new("/api/users", "GET")
    scheme = Endpoint.new("myapp://host/path", "GET")
    scheme.protocol = "mobile-scheme"
    scheme.details.technology = "android"

    builder = build_adb_builder
    builder.print([http, scheme])
    out = builder.io.to_s

    out.should_not contain("/api/users")
    out.should contain("myapp://host/path")
  end

  it "skips iOS-originated schemes (adb is Android-only)" do
    ios = Endpoint.new("myiosapp://open", "GET")
    ios.protocol = "mobile-scheme"
    ios.details.technology = "ios"
    android = Endpoint.new("myapp://host/path", "GET")
    android.protocol = "mobile-scheme"
    android.details.technology = "android"

    builder = build_adb_builder
    builder.print([ios, android])
    out = builder.io.to_s

    out.should_not contain("myiosapp://open")
    out.should contain("myapp://host/path")
  end

  it "treats an Android intent endpoint as Android regardless of technology" do
    intent = Endpoint.new("intent://com.example.app/.FooActivity", "GET")
    intent.protocol = "android-intent"
    intent.details.technology = "android"

    builder = build_adb_builder
    builder.print([intent])
    out = builder.io.to_s.strip

    out.should eq("adb shell am start -n 'com.example.app/.FooActivity'")
  end

  it "classifies well_known App Links by their backing file and skips the bare path" do
    # Android assetlinks.json association and an Apple AASA association both
    # surface as `/*` universal links under the well_known_applinks tech.
    android_link = Endpoint.new("/*", "GET", Details.new(PathInfo.new("app/.well-known/assetlinks.json")))
    android_link.protocol = "universal-link"
    android_link.details.technology = "well_known_applinks"

    ios_link = Endpoint.new("/buy/*", "GET", Details.new(PathInfo.new("app/apple-app-site-association")))
    ios_link.protocol = "universal-link"
    ios_link.details.technology = "well_known_applinks"

    builder = build_adb_builder
    builder.print([android_link, ios_link])
    out = builder.io.to_s

    # Both are bare path patterns with no launchable scheme, so neither emits
    # an adb command — but they are accounted for in different skip buckets.
    out.strip.should be_empty
  end
end
