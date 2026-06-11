require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/mobile/well_known.cr"

describe "Analyzer::Mobile::WellKnown" do
  options = create_test_options
  base = File.expand_path(File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "well_known", ".well-known"))

  CodeLocator.instance.clear("android-assetlinks")
  CodeLocator.instance.clear("ios-aasa")
  CodeLocator.instance.push("android-assetlinks", File.join(base, "assetlinks.json"))
  CodeLocator.instance.push("ios-aasa", File.join(base, "apple-app-site-association"))
  endpoints = Analyzer::Mobile::WellKnown.new(options).analyze

  find = ->(url : String) { endpoints.find { |e| e.url == url } }

  it "emits a /* universal link for an assetlinks handle_all_urls grant" do
    ep = find.call("/*").not_nil!
    ep.protocol.should eq("universal-link")
    ep.metadata.not_nil!["package"].should eq("com.example.myapp")
  end

  it "ignores non-android_app / non-handle_all_urls assetlinks statements" do
    # The web get_login_creds statement must not add a second endpoint or
    # leak its site into the package metadata.
    endpoints.count { |e| e.url == "/*" }.should eq(1)
    find.call("/*").not_nil!.metadata.not_nil!["package"].should_not contain("example.com")
  end

  it "maps AASA legacy paths to universal links" do
    find.call("/buy/*").not_nil!.protocol.should eq("universal-link")
    find.call("/help/website/*").not_nil!.protocol.should eq("universal-link")
  end

  it "strips the NOT prefix and tags the excluded path" do
    ep = find.call("/private/*").not_nil!
    ep.tags.map(&.name).should contain("excluded")
  end

  it "records the associated appID as package metadata" do
    find.call("/buy/*").not_nil!.metadata.not_nil!["package"].should eq("ABCDE12345.com.example.myapp")
  end

  it "maps AASA components and extracts their query matchers" do
    ep = find.call("/articles/*").not_nil!
    ep.protocol.should eq("universal-link")
    ep.params.any? { |p| p.name == "articleNumber" && p.param_type == "query" }.should be_true
  end

  it "tags components flagged exclude: true" do
    find.call("/secret/*").not_nil!.tags.map(&.name).should contain("excluded")
  end
end
