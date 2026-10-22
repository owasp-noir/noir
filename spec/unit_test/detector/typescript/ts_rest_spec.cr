require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/*"

describe "Detect TypeScript ts-rest" do
  options = create_test_options
  instance = Detector::Typescript::TsRest.new options

  it "package.json dependency" do
    instance.detect("package.json", "{\"dependencies\": {\"@ts-rest/core\": \"^3.52.0\"}}").should be_true
  end

  it "@ts-rest/core import" do
    instance.detect("src/contract.ts", "import { initContract } from '@ts-rest/core';").should be_true
  end

  it "server adapter alone" do
    instance.detect("src/main.ts", "import { createExpressEndpoints } from '@ts-rest/express';").should be_false
  end

  it "mention without import" do
    instance.detect("notes.ts", "// see @ts-rest/core docs").should be_false
  end
end
