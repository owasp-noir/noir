require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/models/locator_keys"
require "../../../src/analyzer/analyzers/mobile/ios.cr"

# The iOS analyzer resolves `$(BUILD_SETTING)` placeholders in a URL scheme
# out of `.xcconfig` / `project.pbxproj` files. It prefers the scanned-file
# index, but falls back to globbing the project root when the index is
# empty — i.e. when it runs without a detector pass in front of it, which
# is exactly the case where nothing else has applied `--exclude-path`. That
# fallback used to read build settings out of files the user had excluded.
describe "Analyzer::Mobile::Ios --exclude-path" do
  base = File.expand_path(File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "ios"))

  analyze = ->(exclude : String) do
    options = create_test_options
    options["exclude_path"] = YAML::Any.new(exclude)
    CodeLocator.instance.clear(Noir::LocatorKeys::IOS_INFO_PLIST)
    CodeLocator.instance.clear(Noir::LocatorKeys::IOS_ENTITLEMENTS)
    # Empty file_map: this is the "no scan context" state that selects the
    # glob fallback in `load_xcconfig_vars`.
    CodeLocator.instance.reset_files
    CodeLocator.instance.push(Noir::LocatorKeys::IOS_INFO_PLIST, File.join(base, "Info.plist"))
    CodeLocator.instance.push(Noir::LocatorKeys::IOS_ENTITLEMENTS, File.join(base, "App.entitlements"))
    Analyzer::Mobile::Ios.new(options).analyze.map(&.url)
  end

  it "resolves a scheme from .xcconfig when nothing is excluded" do
    analyze.call("").should contain("resolvedscheme://")
  end

  it "does not read build settings out of an excluded .xcconfig" do
    urls = analyze.call("Config.xcconfig")
    # Unresolved placeholders are dropped rather than emitted verbatim, so
    # the scheme disappears entirely.
    urls.should_not contain("resolvedscheme://")
    # project.pbxproj is untouched by the pattern and still resolves.
    urls.should contain("pbxscheme://")
  end

  it "does not read build settings out of an excluded project.pbxproj" do
    urls = analyze.call("project.pbxproj")
    urls.should_not contain("pbxscheme://")
    urls.should contain("resolvedscheme://")
  end
end
