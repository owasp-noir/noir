require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/*"

describe "Detect TypeScript oRPC" do
  options = create_test_options
  instance = Detector::Typescript::Orpc.new options

  it "package.json dependency" do
    instance.detect("package.json", "{\"dependencies\": {\"@orpc/server\": \"^1.9.0\"}}").should be_true
  end

  it "@orpc/server import" do
    instance.detect("src/router.ts", "import { os } from '@orpc/server';").should be_true
  end

  it "@orpc/contract import" do
    instance.detect("src/contract.ts", "import { oc } from \"@orpc/contract\";").should be_true
  end

  it "client-only import" do
    instance.detect("src/client.ts", "import { createORPCClient } from '@orpc/client';").should be_false
  end
end
