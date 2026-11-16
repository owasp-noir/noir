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

  it "detects every supported JavaScript and TypeScript source extension" do
    %w[.js .mjs .cjs .jsx .ts .mts .cts .tsx].each do |extension|
      path = "app#{extension}"
      instance.applicable?(path).should be_true
      instance.detect(path, "import { Elysia } from 'elysia'").should be_true
    end
    instance.detect("notes.txt", "import { Elysia } from 'elysia'").should be_false
  end
end
