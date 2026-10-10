require "../../../spec_helper"
require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# Wolverine.Http" do
  options = create_test_options
  instance = Detector::CSharp::Wolverine.new options

  it "WolverineFx.Http package reference" do
    instance.detect("Api.csproj", "<PackageReference Include=\"WolverineFx.Http\" Version=\"3.6.0\" />").should be_true
  end

  it "using Wolverine.Http" do
    instance.detect("OrderEndpoints.cs", "using Wolverine.Http;\npublic static class E {}").should be_true
  end

  it "MapWolverineEndpoints" do
    instance.detect("Program.cs", "app.MapWolverineEndpoints();").should be_true
  end

  it "messaging-only Wolverine" do
    instance.detect("Api.csproj", "<PackageReference Include=\"WolverineFx\" Version=\"3.6.0\" />").should be_false
    instance.detect("Program.cs", "using Wolverine;\nbuilder.Host.UseWolverine();").should be_false
  end
end
