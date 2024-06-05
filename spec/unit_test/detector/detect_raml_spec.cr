require "../../../src/detector/detectors/*"

describe "Detect RAML" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = DetectorRAML.new options

  it "raml" do
    instance.detect("app.yaml", "#%RAML\nApp: 1").should eq(true)
  end

  it "code_locator" do
    locator = CodeLocator.instance
    locator.clear "raml-spec"
    instance.detect("app.yaml", "#%RAML\nApp: 1")
    locator.all("raml-spec").should eq(["app.yaml"])
  end
end
