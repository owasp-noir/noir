require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Tyk API definitions" do
  options = create_test_options
  instance = Detector::Specification::Tyk.new options

  it "detects a classic JSON API definition and registers the path" do
    CodeLocator.instance.clear Noir::LocatorKeys::TYK_SPEC
    content = %({"api_id": "a", "proxy": {"listen_path": "/a/"}})
    instance.detect("apps/a.json", content).should be_true
    CodeLocator.instance.all(Noir::LocatorKeys::TYK_SPEC).should eq(["apps/a.json"])
  end

  it "detects a Tyk Operator ApiDefinition" do
    content = "apiVersion: tyk.tyk.io/v1alpha1\nkind: ApiDefinition\nspec:\n  proxy:\n    listen_path: /a\n"
    instance.detect("api.yaml", content).should be_true
  end

  it "rejects JSON without an API definition" do
    instance.detect("package.json", %({"name": "x", "proxy": {"listen_path": "/a"}})).should be_false
  end

  it "rejects other Kubernetes resources" do
    instance.detect("deploy.yaml", "apiVersion: apps/v1\nkind: Deployment\n").should be_false
  end
end
