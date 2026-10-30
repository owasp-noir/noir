require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go PocketBase" do
  options = create_test_options
  instance = Detector::Go::Pocketbase.new options

  it "go.mod with pocketbase dependency" do
    instance.detect("go.mod", "require github.com/pocketbase/pocketbase v0.22.0").should be_true
  end

  it "go.mod without pocketbase dependency" do
    instance.detect("go.mod", "require github.com/gin-gonic/gin v1.9.0").should be_false
  end

  it "a .go file importing pocketbase router" do
    instance.detect("main.go", "import \"github.com/pocketbase/pocketbase/tools/router\"").should be_true
  end

  it "a .go file importing pocketbase without tools/router" do
    instance.detect("main.go", "import \"github.com/pocketbase/pocketbase\"").should be_false
  end

  it "a .go file without pocketbase import" do
    instance.detect("main.go", "import \"github.com/gin-gonic/gin\"").should be_false
  end

  it "ignores unrelated file" do
    instance.detect("README.md", "github.com/pocketbase/pocketbase").should be_false
  end
end
