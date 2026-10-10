require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/expo_router"

describe "Detect JS Expo Router" do
  options = create_test_options
  instance = Detector::Javascript::ExpoRouter.new options

  it "detects a +api module under app/" do
    instance.applicable?("app/api/users+api.ts").should be_true
    instance.detect("/repo/app/api/users+api.ts", "export async function GET() {}").should be_true
    instance.detect("/repo/src/app/(admin)/health/index+api.js", "").should be_true
  end

  it "does not detect a client-only Expo app" do
    instance.detect("/repo/package.json", %({"dependencies": {"expo-router": "~4.0.0"}})).should be_false
    instance.detect("/repo/app/index.tsx", %(import { Stack } from "expo-router";)).should be_false
  end

  it "does not detect a +api module outside app/" do
    instance.detect("/repo/lib/proxy+api.ts", "export async function GET() {}").should be_false
  end
end
