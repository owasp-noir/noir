require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Egg.js" do
  options = create_test_options
  instance = Detector::Javascript::Egg.new options

  it "package.json dependency, runner or config block" do
    instance.detect("package.json", %({"dependencies": {"egg": "^3.17.0"}})).should be_true
    instance.detect("package.json", %({"devDependencies": {"@eggjs/bin": "^7.0.0"}})).should be_true
    instance.detect("package.json", %({"egg": {"typescript": true}})).should be_true
  end

  it "typescript import" do
    instance.detect("app/controller/home.ts", %(import { Controller } from 'egg';)).should be_true
  end

  it "ignores egg-prefixed plugins and other packages" do
    instance.detect("package.json", %({"dependencies": {"egg-mysql": "^4.0.0"}})).should be_false
    instance.detect("index.js", %(const egg = require('eggplant');)).should be_false
  end
end
