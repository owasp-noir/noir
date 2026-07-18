require "../../../spec_helper"
require "../../../../src/detector/detectors/asp/*"

describe "Detect Classic ASP" do
  options = create_test_options
  instance = Detector::Asp::Classic.new options

  it "detects the page language directive" do
    content = <<-ASP
      <%@LANGUAGE="VBSCRIPT" CODEPAGE="65001"%>
      <html><body>hello</body></html>
      ASP
    instance.detect("default.asp", content).should be_true
  end

  it "detects intrinsic objects inside script delimiters" do
    content = <<-ASP
      <%
      dim id : id = Request.QueryString("id")
      Response.Write id
      %>
      ASP
    instance.detect("view.asp", content).should be_true
  end

  it "detects server-side script blocks in global.asa" do
    content = <<-ASP
      <script runat="server" language="vbscript">
      sub Application_onStart
      end sub
      </script>
      ASP
    instance.detect("global.asa", content).should be_true
  end

  it "does not detect other extensions" do
    content = <<-ASP
      <% dim id : id = Request.QueryString("id") %>
      ASP
    instance.detect("Default.aspx", content).should be_false
  end

  it "does not detect plain markup" do
    content = <<-ASP
      <html><body><h1>Static page</h1></body></html>
      ASP
    instance.detect("index.asp", content).should be_false
  end
end
