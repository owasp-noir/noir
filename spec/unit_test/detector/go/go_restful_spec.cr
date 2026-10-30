require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go go-restful" do
  options = create_test_options
  instance = Detector::Go::GoRestful.new options

  it "go.mod with go-restful dependency" do
    instance.detect("go.mod", "require github.com/emicklei/go-restful/v3 v3.12.0").should be_true
  end

  it "go.mod without go-restful dependency" do
    instance.detect("go.mod", "require github.com/gin-gonic/gin v1.9.0").should be_false
  end

  it "a .go file importing go-restful" do
    instance.detect("main.go", "import \"github.com/emicklei/go-restful/v3\"").should be_true
  end

  it "a .go file without go-restful import" do
    instance.detect("main.go", "import \"github.com/gin-gonic/gin\"").should be_false
  end

  it "ignores unrelated file" do
    instance.detect("README.md", "github.com/emicklei/go-restful").should be_false
  end
end
