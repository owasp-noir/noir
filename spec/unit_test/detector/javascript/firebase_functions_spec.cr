require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Firebase Functions" do
  options = create_test_options
  instance = Detector::Javascript::FirebaseFunctions.new options

  it "v1 require" do
    instance.detect("index.js", %(const functions = require("firebase-functions");)).should be_true
  end

  it "v2 subpath import" do
    instance.detect("index.ts", %(import { onRequest } from "firebase-functions/v2/https";)).should be_true
  end

  it "ignores firebase-admin and non-js files" do
    instance.detect("index.js", %(const admin = require("firebase-admin");)).should be_false
    instance.detect("package.json", %("firebase-functions": "^6.0.0")).should be_false
  end
end
