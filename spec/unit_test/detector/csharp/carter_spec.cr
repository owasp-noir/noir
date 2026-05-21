require "../../../spec_helper"
require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# Carter" do
  options = create_test_options
  instance = Detector::CSharp::Carter.new options

  it "csproj package reference" do
    instance.detect("CarterDemo.csproj", "<PackageReference Include=\"Carter\" Version=\"8.0.0\" />").should be_true
  end

  it "csproj rejects unrelated packages" do
    instance.detect("Other.csproj", "<PackageReference Include=\"Cartography\" />").should be_false
  end

  it "module file uses Carter" do
    instance.detect("Modules/UsersModule.cs", "using Carter;\npublic class UsersModule : ICarterModule {}").should be_true
  end

  it "module file declares ICarterModule" do
    instance.detect("Modules/UsersModule.cs", "public class UsersModule : ICarterModule {}").should be_true
  end

  it "plain ASP.NET controller does not match" do
    instance.detect("Controllers/HomeController.cs", "public class HomeController : Controller {}").should be_false
  end
end
