require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Elysia" do
  options = create_test_options
  instance = Detector::Javascript::Elysia.new options

  it "detects elysia import" do
    instance.detect("index.ts", "import { Elysia } from 'elysia'").should be_true
    instance.detect("index.js", "const { Elysia } = require('elysia')").should be_true
  end

  it "detects elysia package.json dependency" do
    instance.detect("package.json", "{\"dependencies\": {\"elysia\": \"^1.0.0\"}}").should be_true
  end
end
