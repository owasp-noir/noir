require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/mobile/ios.cr"

# Regression coverage for project-generator tooling (Tuist / XcodeGen / Bazel's
# rules_apple) that ships no `.xcodeproj` / `.xcworkspace` — build settings then
# live in a directory that isn't an ancestor of the Info.plist / entitlements,
# so `xcode_project_root` never finds them. The analyzer must still resolve
# `$(VAR)` placeholders by searching the scan's configured base path.
describe "Analyzer::Mobile::Ios (generated project, no .xcodeproj)" do
  options = create_test_options
  base = File.expand_path(File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "ios_generated_project"))
  options["base"] = YAML::Any.new([YAML::Any.new(base)])

  CodeLocator.instance.clear("ios-info-plist")
  CodeLocator.instance.clear("ios-entitlements")
  # No .swift/.m/.mm fixtures belong to this spec — clear file_map so a
  # leftover registration from another spec run earlier in the same
  # process can't feed the code-level route harvesting pass below.
  CodeLocator.instance.clear("file_map")
  CodeLocator.instance.push("ios-info-plist", File.join(base, "App", "Info.plist"))
  CodeLocator.instance.push("ios-entitlements", File.join(base, "App", "App.entitlements"))
  endpoints = Analyzer::Mobile::Ios.new(options).analyze

  find = ->(url : String) { endpoints.find { |e| e.url == url } }

  it "resolves an xcconfig scheme placeholder from a sibling Configs/ directory" do
    find.call("generatedapptalk://").not_nil!.protocol.should eq("mobile-scheme")
    find.call("$(URL_SCHEME_DOMAIN_PREFIX)talk://").should be_nil
  end

  it "resolves an xcconfig associated-domain placeholder in entitlements" do
    find.call("https://generated.example.com/").not_nil!.protocol.should eq("universal-link")
  end
end
