require "../../../spec_helper"
require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# ABP Framework" do
  options = create_test_options
  instance = Detector::CSharp::Abp.new options

  it "csproj Volo.Abp package reference" do
    instance.detect("Acme.Application.csproj", "<PackageReference Include=\"Volo.Abp.Ddd.Application\" Version=\"8.3.0\" />").should be_true
  end

  it "csproj without ABP" do
    instance.detect("Other.csproj", "<PackageReference Include=\"Serilog\" />").should be_false
  end

  it "conventional controller registration" do
    instance.detect("HostModule.cs", "options.ConventionalControllers.Create(typeof(AppModule).Assembly);").should be_true
  end

  it "application service importing Volo.Abp" do
    instance.detect("BookAppService.cs", "using Volo.Abp.Application.Services;\npublic class BookAppService : ApplicationService {}").should be_true
  end

  it "CRUD application service" do
    instance.detect("AuthorAppService.cs", "using Volo.Abp.Application.Services;\npublic class AuthorAppService : CrudAppService<Author, AuthorDto, Guid> {}").should be_true
  end

  it "ApplicationService base without Volo.Abp" do
    instance.detect("BookAppService.cs", "public class BookAppService : ApplicationService {}").should be_false
  end

  it "plain ASP.NET controller" do
    instance.detect("HomeController.cs", "using Microsoft.AspNetCore.Mvc;\npublic class HomeController : Controller {}").should be_false
  end
end
