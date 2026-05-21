require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# FastEndpoints" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::CSharp::FastEndpoints.new options

  it "csproj reference" do
    instance.detect("MyApp.csproj", "<PackageReference Include=\"FastEndpoints\" Version=\"5.30.0\" />").should be_true
  end

  it "program AddFastEndpoints" do
    instance.detect("Program.cs", "builder.Services.AddFastEndpoints();").should be_true
  end

  it "program UseFastEndpoints" do
    instance.detect("Program.cs", "app.UseFastEndpoints();").should be_true
  end

  it "using directive" do
    instance.detect("Endpoint.cs", "using FastEndpoints;\npublic class X : Endpoint<R> { }").should be_true
  end

  it "ignores unrelated files" do
    instance.detect("Other.cs", "namespace X { class Y { } }").should be_false
  end
end
