require "../../../spec_helper"
require "../../../../src/detector/detectors/vb/*"

describe "Detect VB.NET ASP.NET MVC / Web API" do
  options = create_test_options
  instance = Detector::VB::AspNetMvc.new options

  it "web_api_controller" do
    content = <<-VB
      Public Class UsersController
          Inherits ApiController
      End Class
      VB
    instance.detect("UsersController.vb", content).should be_true
  end

  it "mvc_controller_with_qualified_base" do
    content = "Public Class HomeController\n    Inherits System.Web.Mvc.Controller\nEnd Class"
    instance.detect("HomeController.vb", content).should be_true
  end

  it "route_table" do
    content = "config.Routes.MapHttpRoute(name:=\"DefaultApi\", routeTemplate:=\"api/{controller}/{id}\")"
    instance.detect("WebApiConfig.vb", content).should be_true
  end

  it "plain_vb_class" do
    content = "Public Class Customer\n    Inherits EntityBase\nEnd Class"
    instance.detect("Customer.vb", content).should be_false
  end

  it "webforms_code_behind" do
    content = "Partial Class _Default\n    Inherits System.Web.UI.Page\nEnd Class"
    instance.detect("Default.aspx.vb", content).should be_false
  end
end
