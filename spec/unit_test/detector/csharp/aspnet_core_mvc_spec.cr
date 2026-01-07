require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# ASP.Net Core MVC" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::CSharp::AspNetCoreMvc.new options

  it "csproj reference" do
    instance.detect("MyApp.csproj", "<PackageReference Include=\"Microsoft.AspNetCore.Mvc\" />").should be_true
  end

  it "csproj sdk attribute" do
    instance.detect("MyApp.csproj", "<Project Sdk=\"Microsoft.NET.Sdk.Web\"></Project>").should be_true
  end

  it "program setup" do
    instance.detect("Program.cs", "var builder = WebApplication.CreateBuilder(args);\napp.MapControllerRoute(name: \"default\", pattern: \"{controller=Home}/{action=Index}/{id?}\");").should be_true
  end

  it "program map controllers" do
    instance.detect("Program.cs", "app.MapControllers();").should be_true
  end

  it "program add mvc" do
    instance.detect("Program.cs", "builder.Services.AddMvc();").should be_true
  end
end
