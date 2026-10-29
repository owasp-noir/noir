require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Hapi" do
  options = create_test_options
  instance = Detector::Javascript::Hapi.new options

  it "detects hapi imports" do
    instance.detect("index.js", "const Hapi = require('@hapi/hapi')").should be_true
    instance.detect("index.js", "const Hapi = require('hapi')").should be_true
    instance.detect("index.ts", "import Hapi from 'hapi'").should be_true
  end

  # #3291: a Glue / haute-couture app never imports hapi in code.
  it "detects a package.json hapi dependency" do
    instance.detect("package.json", %({"dependencies": {"hapi": "^16.4.3", "glue": "^4.1.0"}})).should be_true
    instance.detect("package.json", %({"dependencies": {"@hapi/hapi": "^21.0.0"}})).should be_true
  end

  it "ignores a package.json without hapi" do
    instance.detect("package.json", %({"dependencies": {"@hapi/joi": "^17.0.0", "hapi-swagger": "^14.0.0"}})).should be_false
  end

  it "ignores code without a hapi marker" do
    instance.detect("index.js", "const joi = require('@hapi/joi')").should be_false
  end
end
