require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/*"

describe "Detect TypeScript Encore" do
  options = create_test_options
  instance = Detector::Typescript::Encore.new options

  it "package.json dependency" do
    instance.detect("package.json", "{\"dependencies\": {\"encore.dev\": \"^1.41.0\"}}").should be_true
  end

  it "encore.dev/api import" do
    instance.detect("hello/hello.ts", "import { api } from \"encore.dev/api\";").should be_true
  end

  it "mention without import" do
    instance.detect("notes.ts", "// ported from encore.dev examples").should be_false
  end

  it "package.json without the dependency" do
    instance.detect("package.json", "{\"homepage\": \"https://encore.dev\"}").should be_false
  end
end
