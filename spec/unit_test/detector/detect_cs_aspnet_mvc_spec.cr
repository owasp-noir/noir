require "../../../src/detector/detectors/*"

describe "Detect C# ASP.Net MVC" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = DetectorCSharpAspNetMvc.new options

  it "packages" do
    instance.detect("packages.config", "Microsoft.AspNet.Mvc").should eq(true)
  end
end
