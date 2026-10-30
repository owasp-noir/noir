require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go GoFrame" do
  options = create_test_options
  instance = Detector::Go::Gf.new options

  it "go.mod with GoFrame dependency" do
    instance.detect("go.mod", "require github.com/gogf/gf/v2 v2.7.0").should be_true
  end

  it "go.mod without GoFrame dependency" do
    instance.detect("go.mod", "require github.com/gin-gonic/gin v1.9.0").should be_false
  end

  it "a .go file importing GoFrame" do
    instance.detect("main.go", "import \"github.com/gogf/gf/v2/net/ghttp\"").should be_true
  end

  it "a .go file without GoFrame import" do
    instance.detect("main.go", "import \"github.com/gin-gonic/gin\"").should be_false
  end

  it "ignores unrelated file" do
    instance.detect("README.md", "github.com/gogf/gf").should be_false
  end
end
