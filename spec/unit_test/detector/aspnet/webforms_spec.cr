require "../../../spec_helper"
require "../../../../src/detector/detectors/aspnet/*"

describe "Detect ASP.NET WebForms" do
  options = create_test_options
  instance = Detector::Aspnet::WebForms.new options

  it "detects a multi-line Page directive" do
    content = <<-ASPX
      <%@ Page
          Language="VB"
          AutoEventWireup="true"
          CodeFile="Default.aspx.vb"
          Inherits="_Default" %>
      ASPX
    instance.detect("Default.aspx", content).should be_true
  end

  it "detects WebHandler directives" do
    content = <<-ASHX
      <%@ WebHandler Language="VB" Class="Image" %>
      ASHX
    instance.detect("Image.ashx", content).should be_true
  end

  it "detects server controls in user controls" do
    content = <<-ASCX
      <asp:TextBox ID="txtTerm" runat="server" />
      ASCX
    instance.detect("Search.ascx", content).should be_true
  end

  it "detects page code-behind" do
    content = <<-VB
      Partial Class _Default
          Inherits System.Web.UI.Page
      End Class
      VB
    instance.detect("Default.aspx.vb", content).should be_true
  end

  it "does not detect unrelated sources" do
    content = <<-CS
      public class WeatherController : ControllerBase
      {
          [HttpGet] public string Get() => "ok";
      }
      CS
    instance.detect("WeatherController.cs", content).should be_false
  end

  it "does not detect plain markup" do
    content = <<-ASPX
      <html><body><h1>Static page</h1></body></html>
      ASPX
    instance.detect("about.aspx", content).should be_false
  end
end
