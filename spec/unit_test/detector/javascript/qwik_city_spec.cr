require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/qwik_city"

describe "Detect JS Qwik City" do
  options = create_test_options
  instance = Detector::Javascript::QwikCity.new options

  it "detects package.json with @builder.io/qwik-city" do
    instance.applicable?("package.json").should be_true
    instance.detect("package.json", %({"devDependencies": {"@builder.io/qwik-city": "^1.12.0"}})).should be_true
  end

  it "detects the Qwik 2 router package and the vite plugin" do
    instance.detect("package.json", %({"devDependencies": {"@qwik.dev/router": "^2.0.0"}})).should be_true
    instance.detect("vite.config.ts", %(import { qwikCity } from "@builder.io/qwik-city/vite";)).should be_true
  end

  it "does not detect core Qwik alone" do
    instance.detect("package.json", %({"devDependencies": {"@builder.io/qwik": "^1.12.0"}})).should be_false
  end
end
