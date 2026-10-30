require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Huma" do
  options = create_test_options
  instance = Detector::Go::Huma.new options

  it "go.mod with huma dependency" do
    instance.detect("go.mod", "require github.com/danielgtaylor/huma/v2 v2.27.0").should be_true
  end

  it "go.mod without huma dependency" do
    instance.detect("go.mod", "require github.com/gin-gonic/gin v1.9.0").should be_false
  end

  it "a .go file importing huma" do
    instance.detect("main.go", "import \"github.com/danielgtaylor/huma/v2\"").should be_true
  end

  it "a .go file without huma import" do
    instance.detect("main.go", "import \"github.com/gin-gonic/gin\"").should be_false
  end

  it "ignores unrelated file" do
    instance.detect("README.md", "github.com/danielgtaylor/huma").should be_false
  end
end
