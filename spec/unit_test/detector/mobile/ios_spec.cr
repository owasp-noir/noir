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

  it "ignores an Info.plist without URL types" do
    instance.detect("App/Info.plist", "<key>CFBundleShortVersionString</key>").should be_false
  end

  it "ignores an unrelated *-Info.plist (no URL types)" do
    # `GoogleService-Info.plist` ends with `Info.plist` but declares no
    # CFBundleURLTypes; the content gate keeps it out.
    instance.detect("App/GoogleService-Info.plist", "<key>CLIENT_ID</key>").should be_false
  end

  it "detects entitlements with associated domains" do
    instance.detect("App/App.entitlements", "<key>com.apple.developer.associated-domains</key>").should be_true
  end

  it "is applicable to plist and entitlements paths" do
    instance.applicable?("App/Wikipedia-Info.plist").should be_true
    instance.applicable?("App/App.entitlements").should be_true
    instance.applicable?("App/Main.swift").should be_false
  end
end
