require "../../../spec_helper"
require "../../../../src/detector/detectors/cfml/*"

describe "Detect CFML" do
  options = create_test_options
  instance = Detector::Cfml::Pure.new options

  it "detects tag syntax components" do
    content = <<-CFML
      <cfcomponent output="false">
        <cffunction name="index" access="remote">
          <cfargument name="id" type="numeric" required="true">
        </cffunction>
      </cfcomponent>
      CFML
    instance.detect("Service.cfc", content).should be_true
  end

  it "detects uppercase tags" do
    content = <<-CFML
      <CFSET total = 1>
      <CFOUTPUT>#total#</CFOUTPUT>
      CFML
    instance.detect("total.cfm", content).should be_true
  end

  it "detects script syntax components" do
    content = <<-CFML
      component extends="framework.Proxy" {
        remote string function echo( required string text ) {
          return arguments.text;
        }
      }
      CFML
    instance.detect("Proxy.cfc", content).should be_true
  end

  it "does not detect non-CFML extensions" do
    content = <<-CFML
      <cfcomponent><cffunction name="index"></cffunction></cfcomponent>
      CFML
    instance.detect("Service.java", content).should be_false
  end

  it "does not detect plain markup with no CFML constructs" do
    content = <<-CFML
      <html>
        <body><h1>Static page</h1></body>
      </html>
      CFML
    instance.detect("index.cfm", content).should be_false
  end
end
