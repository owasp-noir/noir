require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/mobile/ios.cr"

describe "Analyzer::Mobile::Ios" do
  options = create_test_options
  base = File.expand_path(File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "ios"))

  CodeLocator.instance.clear("ios-info-plist")
  CodeLocator.instance.clear("ios-entitlements")
  CodeLocator.instance.push("ios-info-plist", File.join(base, "Info.plist"))
  CodeLocator.instance.push("ios-entitlements", File.join(base, "App.entitlements"))
  endpoints = Analyzer::Mobile::Ios.new(options).analyze

  find = ->(url : String) { endpoints.find { |e| e.url == url } }

  it "extracts every scheme in a CFBundleURLSchemes array" do
    find.call("myapp://").not_nil!.protocol.should eq("mobile-scheme")
    find.call("myapp-alt://").not_nil!.protocol.should eq("mobile-scheme")
  end

  it "suppresses generic web schemes registered as URL types" do
    # An app may register `https` (e.g. to be selectable as a browser);
    # a bare `https://` has no host and is not a deep-link entry point.
    find.call("https://").should be_nil
  end

  it "resolves an Xcode build-setting scheme placeholder from .xcconfig" do
    # CFBundleURLSchemes has `$(BUNDLE_URL_SCHEME)`; Config.xcconfig defines
    # `BUNDLE_URL_SCHEME = resolvedscheme`.
    find.call("resolvedscheme://").not_nil!.protocol.should eq("mobile-scheme")
    find.call("$(BUNDLE_URL_SCHEME)://").should be_nil
  end

  it "resolves nested Xcode build-setting scheme placeholders from .xcconfig" do
    # CFBundleURLSchemes has `$(NESTED_BUNDLE_URL_SCHEME)`; Config.xcconfig
    # resolves it through `$(BUNDLE_URL_SCHEME)`.
    find.call("resolvedscheme-nested://").not_nil!.protocol.should eq("mobile-scheme")
    find.call("$(NESTED_BUNDLE_URL_SCHEME)://").should be_nil
  end

  it "resolves project.pbxproj build-setting scheme placeholders for multiple app flavors" do
    find.call("pbxscheme://").not_nil!.protocol.should eq("mobile-scheme")
    find.call("pbxscheme-alt://").not_nil!.protocol.should eq("mobile-scheme")
    find.call("$(PBXPROJ_URL_SCHEME)://").should be_nil
  end

  it "maps applinks: associated domains to universal links" do
    find.call("https://myapp.example.com/").not_nil!.protocol.should eq("universal-link")
  end

  it "strips the ?mode= suffix from an associated domain" do
    find.call("https://www.example.com/").should_not be_nil
  end

  it "ignores non-applinks associated domains (webcredentials)" do
    # webcredentials:myapp.example.com must not create a second entry; the
    # only myapp.example.com endpoint is the applinks one.
    endpoints.count { |e| e.url == "https://myapp.example.com/" }.should eq(1)
  end

  it "maps appclips: associated domains to universal links" do
    # An App Clip is launched by a tapped https:// URL just like a universal
    # link; App Clip targets often list domains the full app does not.
    find.call("https://clip.example.com/").not_nil!.protocol.should eq("universal-link")
  end

  it "collapses an appclips domain that overlaps an applinks domain" do
    # appclips:myapp.example.com + applinks:myapp.example.com are the same
    # https:// surface — one endpoint, not two.
    endpoints.count { |e| e.url == "https://myapp.example.com/" }.should eq(1)
  end
end
