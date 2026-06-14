require "../../../spec_helper"
require "../../../../src/detector/detectors/mobile/*"

describe "Detect Mobile iOS" do
  options = create_test_options
  instance = Detector::Mobile::Ios.new options

  it "detects the default Info.plist with URL types" do
    instance.detect("App/Info.plist", "<key>CFBundleURLTypes</key>").should be_true
  end

  it "detects a <Target>-Info.plist (older Xcode convention)" do
    # Real apps name their plist e.g. `Wikipedia-Info.plist`,
    # `podcasts-Info.plist`; matching only the exact `Info.plist` basename
    # dropped every custom URL scheme in those apps.
    instance.detect("Wikipedia/Wikipedia-Info.plist", "<key>CFBundleURLTypes</key>").should be_true
    instance.detect("podcasts/podcasts-Info.plist", "<key>CFBundleURLTypes</key>").should be_true
  end

  it "detects a fully custom-named info plist (white-label branding)" do
    # nextcloud-ios points INFOPLIST_FILE at `Brand/iOSClient.plist`; the only
    # reliable signal is the CFBundleURLTypes content, not the filename.
    instance.detect("Brand/iOSClient.plist", "<key>CFBundleURLTypes</key>").should be_true
  end

  it "ignores a plist without URL types" do
    instance.detect("App/Info.plist", "<key>CFBundleShortVersionString</key>").should be_false
    instance.detect("App/Settings.bundle/Root.plist", "<key>PreferenceSpecifiers</key>").should be_false
  end

  it "ignores an unrelated plist that happens to end in Info.plist" do
    # `GoogleService-Info.plist` declares no CFBundleURLTypes; the content
    # gate keeps it out.
    instance.detect("App/GoogleService-Info.plist", "<key>CLIENT_ID</key>").should be_false
  end

  it "detects entitlements with associated domains" do
    instance.detect("App/App.entitlements", "<key>com.apple.developer.associated-domains</key>").should be_true
  end

  it "is applicable to plist and entitlements paths" do
    instance.applicable?("Brand/iOSClient.plist").should be_true
    instance.applicable?("App/Wikipedia-Info.plist").should be_true
    instance.applicable?("App/App.entitlements").should be_true
    instance.applicable?("App/Main.swift").should be_false
  end
end
