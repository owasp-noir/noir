require "../../../spec_helper"
require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# ASP.Net MVC" do
  options = create_test_options
  instance = Detector::CSharp::AspNetMvc.new options

  it "packages.config" do
    instance.detect("packages.config", "<package id=\"Microsoft.AspNet.Mvc\" version=\"5.2.9\" />").should be_true
  end

  it "csproj PackageReference" do
    instance.detect("Web.csproj", "<PackageReference Include=\"Microsoft.AspNet.Mvc\" Version=\"5.2.9\" />").should be_true
  end

  it "csproj Reference" do
    instance.detect("Web.csproj", "<Reference Include=\"System.Web.Mvc, Version=5.2.9.0, Culture=neutral\" />").should be_true
  end

  it "cs controller class" do
    source = <<-CS
      using System.Web.Mvc;

      namespace MyApp.Controllers
      {
          public class HomeController : Controller
          {
              public ActionResult Index()
              {
                  return View();
              }
          }
      }
      CS
    instance.detect("Controllers/HomeController.cs", source).should be_true
  end

  it "cs RouteConfig with MapRoute" do
    source = <<-CS
      using System.Web.Mvc;
      using System.Web.Routing;

      public class RouteConfig
      {
          public static void RegisterRoutes(RouteCollection routes)
          {
              routes.MapRoute("Default", "{controller}/{action}/{id}");
          }
      }
      CS
    instance.detect("App_Start/RouteConfig.cs", source).should be_true
  end

  it "does not match file with using System.Web.Mvc and ControllerBase" do
    source = <<-CS
      using System.Web.Mvc;

      namespace MyApp.Controllers
      {
          public class UsersController : ControllerBase
          {
              public ActionResult GetAll()
              {
                  return Ok();
              }
          }
      }
      CS
    instance.detect("Controllers/UsersController.cs", source).should be_false
  end

  it "does not match ASP.NET Core csproj" do
    source = <<-XML
      <Project Sdk="Microsoft.NET.Sdk.Web">
        <ItemGroup>
          <PackageReference Include="Microsoft.AspNetCore.Mvc" Version="2.2.0" />
        </ItemGroup>
      </Project>
      XML
    instance.detect("MyApp.csproj", source).should be_false
  end

  it "does not match ASP.NET Core controller" do
    source = <<-CS
      using Microsoft.AspNetCore.Mvc;

      namespace MyApp.Controllers
      {
          [ApiController]
          [Route("api/[controller]")]
          public class UsersController : ControllerBase
          {
              [HttpGet]
              public ActionResult GetAll()
              {
                  return Ok();
              }
          }
      }
      CS
    instance.detect("Controllers/UsersController.cs", source).should be_false
  end

  it "does not match unrelated cs file" do
    source = <<-CS
      using System;

      public class Utils
      {
          public static void DoWork() {}
      }
      CS
    instance.detect("Utils.cs", source).should be_false
  end
end
