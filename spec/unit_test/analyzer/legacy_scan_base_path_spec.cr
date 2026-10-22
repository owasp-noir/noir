require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# Convention filters ("this file is an `#include` fragment", "this
# component is a test suite") were applied to the absolute path, so the
# directory a checkout happened to live in decided whether its endpoints
# were reported at all. Both analyzers now match on the scan-base-relative
# path instead.
private def scan_tree(root : String) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.reset_files
end

private def write_file(path : String, content : String)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content)
end

describe "legacy analyzers and the scan base path" do
  it "reports Classic ASP pages from a base path that contains an `inc` segment" do
    root = File.tempname("noir-asp-base")
    site = File.join(root, "inc", "site")

    begin
      write_file(File.join(site, "login.asp"), <<-ASP)
        <%@ Language="VBScript" %>
        <%
          Dim user
          user = Request.QueryString("user")
          Response.Write user
        %>
        ASP

      endpoints = scan_tree(site)
      urls = endpoints.select { |endpoint| endpoint.details.technology == "asp_classic" }.map(&.url)

      urls.should contain("/login.asp")
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end

  it "reports CFML components from a base path that contains a `test` segment" do
    root = File.tempname("noir-cfml-base")
    app = File.join(root, "test", "app")

    begin
      write_file(File.join(app, "resources", "Echo.cfc"), <<-CFML)
        component extends="taffy.core.resource" taffy:uri="/echo" {

        	function get( string message = "" ) {
        		return representationOf( { "message" : arguments.message } );
        	}

        }
        CFML

      endpoints = scan_tree(app)
      urls = endpoints.select { |endpoint| endpoint.details.technology == "cfml_taffy" }.map(&.url)

      urls.should contain("/echo")
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end

  it "reports ASP.NET MVC controllers from a base path that contains `RouteConfig`" do
    root = File.tempname("noir-mvc-base")
    app = File.join(root, "x_RouteConfig_demo")

    begin
      write_file(File.join(app, "App_Start", "RouteConfig.cs"), <<-CS)
        using System.Web.Mvc;
        using System.Web.Routing;
        public class RouteConfig {
          public static void RegisterRoutes(RouteCollection routes) {
            routes.MapRoute(name: "Default", url: "{controller}/{action}/{id}");
          }
        }
        CS
      write_file(File.join(app, "Controllers", "HomeController.cs"), <<-CS)
        using System.Web.Mvc;
        public class HomeController : Controller {
          public ActionResult Index() { return View(); }
        }
        CS

      endpoints = scan_tree(app)
      urls = endpoints.select { |endpoint| endpoint.details.technology == "cs_aspnet_mvc" }.map(&.url)

      urls.should contain("/Home/Index")
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end

  it "leaves an ASP.NET Core project's controllers to the Core analyzer" do
    root = File.tempname("noir-mvc-mixed")

    begin
      write_file(File.join(root, "Legacy", "packages.config"), %(<packages><package id="Microsoft.AspNet.Mvc" version="5.2.7" /></packages>))
      write_file(File.join(root, "Legacy", "Controllers", "LegacyController.cs"), <<-CS)
        using System.Web.Mvc;
        public class LegacyController : Controller {
          public ActionResult Index() { return View(); }
        }
        CS
      # Usings come from GlobalUsings.cs, so the controller names no namespace.
      write_file(File.join(root, "Core", "Core.csproj"), %(<Project Sdk="Microsoft.NET.Sdk.Web"></Project>))
      write_file(File.join(root, "Core", "GlobalUsings.cs"), "global using Microsoft.AspNetCore.Mvc;\n")
      write_file(File.join(root, "Core", "Controllers", "ShopController.cs"), <<-CS)
        public class ShopController : Controller {
          public async Task<ViewResult> Details(int id) => View();
        }
        CS

      urls = scan_tree(root).select { |endpoint| endpoint.details.technology == "cs_aspnet_mvc" }.map(&.url)

      urls.should contain("/Legacy/Index")
      urls.any?(&.starts_with?("/Shop")).should be_false
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end

  it "keeps MVC 5 controllers in web SDK, migration and colliding-base layouts" do
    root = File.tempname("noir-mvc-layouts")

    begin
      # Multi-targeted web SDK project that still builds MVC 5.
      write_file(File.join(root, "Multi", "Multi.csproj"), <<-XML)
        <Project Sdk="Microsoft.NET.Sdk.Web"><PropertyGroup><TargetFrameworks>net48;net8.0</TargetFrameworks></PropertyGroup>
        <ItemGroup><PackageReference Include="Microsoft.AspNet.Mvc" Version="5.2.9" /></ItemGroup></Project>
        XML
      write_file(File.join(root, "Multi", "Controllers", "MultiController.cs"), <<-CS)
        using System.Web.Mvc;
        public class MultiController : Controller { public ActionResult Index() { return View(); } }
        CS
      # Incremental migration: a classic project referencing SystemWebAdapters.
      write_file(File.join(root, "Adapters", "Adapters.csproj"), <<-XML)
        <Project ToolsVersion="15.0"><ItemGroup><Reference Include="System.Web.Mvc" />
        <PackageReference Include="Microsoft.AspNetCore.SystemWebAdapters" Version="1.3.0" /></ItemGroup></Project>
        XML
      write_file(File.join(root, "Adapters", "Controllers", "AdaptedController.cs"), <<-CS)
        using System.Web.Mvc;
        public class AdaptedController : Controller { public ActionResult Index() { return View(); } }
        CS
      # Same base name in a Web API project, and a base outside Controllers/.
      write_file(File.join(root, "Api", "Controllers", "BaseController.cs"), <<-CS)
        using System.Web.Http;
        public abstract class BaseController : ApiController { }
        CS
      write_file(File.join(root, "Web", "packages.config"), %(<packages><package id="Microsoft.AspNet.Mvc" version="5.2.7" /></packages>))
      write_file(File.join(root, "Web", "Controllers", "BaseController.cs"), <<-CS)
        using System.Web.Mvc;
        public abstract class BaseController : Controller { }
        CS
      write_file(File.join(root, "Web", "Infrastructure", "SecureBase.cs"), <<-CS)
        using System.Web.Mvc;
        public abstract class SecureBase : Controller { }
        CS
      write_file(File.join(root, "Web", "Controllers", "HomeController.cs"), <<-CS)
        using System.Web.Mvc;
        public class HomeController : BaseController { public ActionResult Index() { return View(); } }
        public class OrdersController : SecureBase { public ActionResult List() { return View(); } }
        CS

      urls = scan_tree(root).select { |endpoint| endpoint.details.technology == "cs_aspnet_mvc" }.map(&.url)

      %w[/Multi/Index /Adapted/Index /Home/Index /Orders/List].each { |url| urls.should contain(url) }
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
