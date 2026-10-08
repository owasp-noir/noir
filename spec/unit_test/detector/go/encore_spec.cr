require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Encore" do
  options = create_test_options
  instance = Detector::Go::Encore.new options

  it "go.mod require" do
    instance.detect("go.mod", "module encore.app\n\nrequire encore.dev v1.41.0").should be_true
  end

  it "encore.dev import" do
    instance.detect("hello/hello.go", "import \"encore.dev/rlog\"").should be_true
  end

  it "//encore:api directive" do
    instance.detect("hello/hello.go", "package hello\n\n//encore:api public\nfunc Ping() {}").should be_true
  end

  it "mention in a comment" do
    instance.detect("main.go", "// see https://encore.dev for docs\npackage main").should be_false
  end
end
