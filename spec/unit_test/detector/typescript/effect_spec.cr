require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/*"

describe "Detect TypeScript Effect HttpApi" do
  options = create_test_options
  instance = Detector::Typescript::Effect.new options

  it "@effect/platform HttpApi" do
    instance.detect("src/api.ts", "import { HttpApiEndpoint, HttpApiGroup } from \"@effect/platform\"").should be_true
  end

  it "effect/unstable/httpapi" do
    instance.detect("src/api.ts", "import { HttpApiEndpoint } from \"effect/unstable/httpapi\"").should be_true
  end

  it "@effect/platform HttpApi subpath import" do
    instance.detect("src/api.ts", "import * as HttpApiEndpoint from \"@effect/platform/HttpApiEndpoint\"").should be_true
  end

  it "@effect/platform without HttpApi" do
    instance.detect("src/client.ts", "import { HttpClient, FileSystem } from \"@effect/platform\"").should be_false
  end

  it "HttpApiEndpoint name without the import" do
    instance.detect("src/notes.ts", "// HttpApiEndpoint is from Effect").should be_false
  end
end
