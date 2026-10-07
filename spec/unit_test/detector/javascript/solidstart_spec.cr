require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/solidstart"

describe "Detect JS SolidStart" do
  options = create_test_options
  instance = Detector::Javascript::Solidstart.new options

  it "detects package.json with @solidjs/start" do
    instance.applicable?("package.json").should be_true
    instance.detect("package.json", %({"dependencies": {"@solidjs/start": "^1.1.0"}})).should be_true
  end

  it "detects the app config" do
    instance.detect("app.config.ts", %(import { defineConfig } from "@solidjs/start/config";)).should be_true
  end

  it "does not detect client-only Solid" do
    instance.detect("package.json", %({"dependencies": {"solid-js": "^1.9.0", "@solidjs/router": "^0.15.0"}})).should be_false
  end
end
