require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Connect" do
  options = create_test_options
  instance = Detector::Go::ConnectRpc.new options

  it "go.mod with connect dependency" do
    instance.detect("go.mod", "require connectrpc.com/connect v1.16.0").should be_true
  end

  it "go.mod without connect dependency" do
    instance.detect("go.mod", "require github.com/gin-gonic/gin v1.9.0").should be_false
  end

  it "a .go file importing connect" do
    instance.detect("main.go", "import \"connectrpc.com/connect\"").should be_true
  end

  it "a .go file without connect import" do
    instance.detect("main.go", "import \"github.com/gin-gonic/gin\"").should be_false
  end

  it "ignores unrelated file" do
    instance.detect("README.md", "connectrpc.com/connect").should be_false
  end
end
