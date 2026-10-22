require "../../../spec_helper"
require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# ServiceStack" do
  options = create_test_options
  instance = Detector::CSharp::ServiceStack.new options

  it "csproj package reference" do
    instance.detect("ServiceStackDemo.csproj", "<PackageReference Include=\"ServiceStack\" Version=\"8.0.0\" />").should be_true
  end

  it "csproj sub-package reference" do
    instance.detect("ServiceStackDemo.csproj", "<PackageReference Include=\"ServiceStack.Kestrel\" Version=\"8.0.0\" />").should be_true
  end

  it "csproj rejects unrelated packages" do
    instance.detect("Other.csproj", "<PackageReference Include=\"Serilog\" />").should be_false
  end

  it "request DTO uses ServiceStack" do
    instance.detect("ServiceModel/Hello.cs", "using ServiceStack;\n[Route(\"/hello\")]\npublic class Hello : IReturn<HelloResponse> {}").should be_true
  end

  it "request DTO implements IReturn<T> without importing the namespace" do
    instance.detect("ServiceModel/Hello.cs", "public class Hello : IReturn<HelloResponse> {}").should be_true
  end

  it "request DTO implements IReturnVoid" do
    instance.detect("ServiceModel/Ping.cs", "public class Ping : IReturnVoid {}").should be_true
  end

  it "AppHost registers routes fluently" do
    instance.detect("AppHost.cs", "public override void Configure(Container c) { Routes.Add<Hello>(\"/hello\"); }").should be_true
  end

  it "AppHost uses the assembly-scanning convention" do
    instance.detect("AppHost.cs", "Routes.AddFromAssembly(typeof(MyServices).Assembly);").should be_true
  end

  it "plain ASP.NET controller does not match" do
    instance.detect("Controllers/HomeController.cs", "[Route(\"api/[controller]\")]\npublic class HomeController : Controller {}").should be_false
  end

  it "unrelated .cs file does not match" do
    instance.detect("Models/User.cs", "public class User { public string Name { get; set; } }").should be_false
  end
end
