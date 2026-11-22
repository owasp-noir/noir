require "spec"
require "../../../src/miniparsers/csharp_minimal_api_config"

describe Noir::CSharpMinimalApiConfig do
  it "retains a literal reader alongside a dynamic one configured in another file" do
    config = Noir::CSharpMinimalApiConfig.new
    config.read("services.AddApiVersioning();")
    config.read(<<-CS)
      services.Configure<ApiVersioningOptions>(o => {
          o.ApiVersionReader = ApiVersionReader.Combine(
              new HeaderApiVersionReader("X-Version"), GetDeploymentReader());
      });
      CS
    config.finish
    config.readers.to_a.should eq([{"header", "X-Version"}])
    config.unknown_reader?.should be_true
  end

  it "leaves the request key unresolved when a callback configures the options" do
    config = Noir::CSharpMinimalApiConfig.new
    config.read("services.AddApiVersioning(options => Configure(options));")
    config.finish
    config.readers.should be_empty
    config.unknown_reader?.should be_true
  end

  it "does not add a query key to URL segment versioning" do
    config = Noir::CSharpMinimalApiConfig.new
    config.read("services.AddApiVersioning(o => o.ApiVersionReader = new UrlSegmentApiVersionReader());")
    config.finish
    config.readers.should be_empty
    config.unknown_reader?.should be_false
  end
end
