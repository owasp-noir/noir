require "../../../spec_helper"
require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# ASP.Net MVC" do
  options = create_test_options
  instance = Detector::CSharp::AspNetMvc.new options

  it "packages" do
    instance.detect("packages.config", "Microsoft.AspNet.Mvc").should eq(true)
  end
end
