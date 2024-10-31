require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# ASP.Net MVC" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::CSharp::AspNetMvc.new options

  it "packages" do
    instance.detect("packages.config", "Microsoft.AspNet.Mvc").should eq(true)
  end
end
