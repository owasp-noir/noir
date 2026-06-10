require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/mobile/android.cr"

# FunctionalTester only checks url / method / protocol / params, so the
# `metadata` hash and path-normalization edge cases are asserted here.
describe "Analyzer::Mobile::Android" do
  options = create_test_options
  manifest = File.expand_path(
    File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "android", "AndroidManifest.xml"))

  CodeLocator.instance.clear("android-manifest")
  CodeLocator.instance.push("android-manifest", manifest)
  endpoints = Analyzer::Mobile::Android.new(options).analyze

  find = ->(url : String) { endpoints.find { |e| e.url == url } }

  it "resolves @string/ scheme references via strings.xml" do
    ep = find.call("myappstr://settings")
    ep.should_not be_nil
    ep.not_nil!.protocol.should eq("mobile-scheme")
  end

  it "normalizes templated {id} segments to :id" do
    find.call("myapp://complex/:id").should_not be_nil
  end

  it "uses pathPrefix as a literal path segment" do
    find.call("myapp://accounts/profile").should_not be_nil
  end

  it "marks an autoVerify https filter as a universal-link" do
    ep = find.call("https://myapp.example.com/complex/:id")
    ep.should_not be_nil
    ep.not_nil!.protocol.should eq("universal-link")
  end

  it "attaches the handling component as metadata[\"via\"]" do
    ep = find.call("myapp://complex/:id").not_nil!
    md = ep.metadata.not_nil!
    md["via"].should eq(".DeepLinkActivity")
    md["action"].should eq("android.intent.action.VIEW")
    md["host"].should eq("complex")
    md["package"].should eq("com.example.myapp")
  end

  it "does not emit a separate intent:// entry for a deep-link component" do
    find.call("intent://com.example.myapp/.DeepLinkActivity").should be_nil
  end

  it "emits a bare intent:// endpoint for an exported, data-less component" do
    ep = find.call("intent://com.example.myapp/.SyncService").not_nil!
    ep.protocol.should eq("android-intent")
    ep.metadata.not_nil!["action"].should eq("com.example.ACTION_SYNC")
  end

  it "does not emit anything for a MAIN/LAUNCHER component" do
    find.call("intent://com.example.myapp/.MainActivity").should be_nil
  end
end
