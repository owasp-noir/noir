require "../../../spec_helper"
require "../../../../src/detector/detectors/cfml/*"

describe "Detect CFML Taffy" do
  options = create_test_options
  instance = Detector::Cfml::Taffy.new options

  it "detects the tag-syntax resource attribute" do
    content = <<-CFML
      <cfcomponent extends="taffy.core.resource" taffy_uri="/artists">
        <cffunction name="get" access="public"></cffunction>
      </cfcomponent>
      CFML
    instance.detect("Artists.cfc", content).should be_true
  end

  it "detects the script-syntax colon spelling" do
    content = <<-CFML
      component extends="taffy.core.resource" taffy:uri="/echo" output="false" {
        function get() {}
      }
      CFML
    instance.detect("Echo.cfc", content).should be_true
  end

  it "detects the api component in the application entry point" do
    content = <<-CFML
      <cfset application.taffy = createObject("component", "taffy.core.api") />
      CFML
    instance.detect("index.cfm", content).should be_true
  end

  it "does not detect plain CFML components" do
    content = <<-CFML
      <cfcomponent output="false">
        <cffunction name="getData" access="public"></cffunction>
      </cfcomponent>
      CFML
    instance.detect("Service.cfc", content).should be_false
  end

  it "does not detect other extensions" do
    content = <<-CFML
      component extends="taffy.core.resource" taffy:uri="/echo" {}
      CFML
    instance.detect("Echo.java", content).should be_false
  end
end
