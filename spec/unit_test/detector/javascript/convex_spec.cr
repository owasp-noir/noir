require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Convex" do
  options = create_test_options
  instance = Detector::Javascript::Convex.new options

  it "package.json dependency" do
    instance.detect("package.json", %({"dependencies": {"convex": "^1.17.0"}})).should be_true
  end

  it "convex/server import" do
    instance.detect("convex/http.ts", %(import { httpRouter } from "convex/server";)).should be_true
  end

  it "ignores convex-prefixed packages" do
    instance.detect("package.json", %({"dependencies": {"convex-helpers": "^0.1.0"}})).should be_false
    instance.detect("index.ts", %(import { ConvexHttpClient } from "convex/browser";)).should be_false
  end
end
