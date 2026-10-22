require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Revel" do
  options = create_test_options
  instance = Detector::Go::Revel.new options

  it "go.mod require" do
    instance.detect("go.mod", "module myapp\n\nrequire github.com/revel/revel v1.1.0").should be_true
  end

  it "revel import" do
    instance.detect("app/controllers/app.go", "import \"github.com/revel/revel\"").should be_true
  end

  it "Play routes file without Revel" do
    instance.detect("conf/routes", "GET /  controllers.HomeController.index").should be_false
    instance.detect("go.mod", "module myapp\n\nrequire github.com/gin-gonic/gin v1.9.0").should be_false
  end
end
