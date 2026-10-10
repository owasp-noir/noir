require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/honox"

describe "Detect JS HonoX" do
  options = create_test_options
  instance = Detector::Javascript::Honox.new options

  it "detects package.json with honox" do
    instance.applicable?("package.json").should be_true
    instance.detect("package.json", %({"dependencies": {"hono": "^4.6.0", "honox": "^0.1.26"}})).should be_true
  end

  it "detects a honox import" do
    instance.detect("app/routes/index.tsx", %(import { createRoute } from 'honox/factory')).should be_true
  end

  it "does not detect plain Hono" do
    instance.detect("package.json", %({"dependencies": {"hono": "^4.6.0", "@hono/node-server": "^1.13.0"}})).should be_false
    instance.detect("src/index.ts", %(import { Hono } from "hono")).should be_false
  end
end
