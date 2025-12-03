require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# ASP.Net Core MVC" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::CSharp::AspNetCoreMvc.new options

  it "csproj reference" do
    instance.detect("MyApp.csproj", "<PackageReference Include=\"Microsoft.AspNetCore.Mvc\" />").should eq(true)
  end

  it "program setup" do
    instance.detect("Program.cs", "var builder = WebApplication.CreateBuilder(args);\napp.MapControllerRoute(name: \"default\", pattern: \"{controller=Home}/{action=Index}/{id?}\");").should eq(true)
  end
end
