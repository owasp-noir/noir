require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Moleculer" do
  options = create_test_options
  instance = Detector::Javascript::Moleculer.new options

  it "package.json dependency" do
    instance.detect("package.json", %({"dependencies": {"moleculer": "^0.14.33"}})).should be_true
    instance.detect("package.json", %({"dependencies": {"moleculer-web": "^0.10.7"}})).should be_true
  end

  it "require or import" do
    instance.detect("services/api.service.js", %(const ApiGateway = require("moleculer-web");)).should be_true
    instance.detect("services/users.service.ts", %(import { ServiceBroker } from "moleculer";)).should be_true
  end

  it "ignores moleculer-prefixed plugins" do
    instance.detect("package.json", %({"dependencies": {"moleculer-db": "^0.8.0"}})).should be_false
  end
end
