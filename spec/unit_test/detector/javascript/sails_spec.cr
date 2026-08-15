require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Sails" do
  options = create_test_options
  instance = Detector::Javascript::Sails.new options

  it "package_json_dependency" do
    instance.detect("package.json", %({"dependencies": {"sails": "^1.5.4"}})).should be_true
  end

  it "package_json_dev_dependency" do
    instance.detect("package.json", %({"devDependencies": {"sails": "^1.5.4"}})).should be_true
  end

  it "package_json_unrelated" do
    instance.detect("package.json", %({"dependencies": {"express": "^4.19.2"}})).should be_false
  end

  it "require_single_quot" do
    instance.detect("app.js", "var sails = require('sails');").should be_true
  end

  it "require_double_quot" do
    instance.detect("app.js", "var sails = require(\"sails\");").should be_true
  end

  it "import_single_quot" do
    instance.detect("app.js", "import sails from 'sails';").should be_true
  end

  it "import_double_quot" do
    instance.detect("app.js", "import sails from \"sails\";").should be_true
  end

  it "sails_lift_call" do
    instance.detect("app.js", "sails.lift({}, function (err) {});").should be_true
  end

  it "unrelated_js_content" do
    instance.detect("app.js", "const express = require('express');").should be_false
  end

  it "ignores_non_js_non_manifest_files" do
    instance.detect("README.md", "require('sails')").should be_false
  end
end
