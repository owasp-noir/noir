require "../../../spec_helper"
require "../../../../src/detector/detectors/cfml/*"

describe "Detect CFML Wheels" do
  options = create_test_options
  instance = Detector::Cfml::Wheels.new options

  it "detects the mapper chain in routes.cfm" do
    content = <<-CFML
      <cfscript>
        mapper()
          .get(name="login", to="sessions##new")
        .end();
      </cfscript>
      CFML
    instance.detect("config/routes.cfm", content).should be_true
  end

  it "detects the resource DSL" do
    content = <<-CFML
      <cfscript>
        mapper().resources("users").wildcard().end();
      </cfscript>
      CFML
    instance.detect("config/routes.cfm", content).should be_true
  end

  it "detects framework components by namespace" do
    content = <<-CFML
      component extends="wheels.controller" {
        function index() {}
      }
      CFML
    instance.detect("controllers/Users.cfc", content).should be_true
  end

  it "does not detect an unrelated routes file" do
    content = <<-CFML
      <cfset request.routes = structNew()>
      CFML
    instance.detect("config/routes.cfm", content).should be_false
  end

  it "does not detect plain CFML components" do
    content = <<-CFML
      <cfcomponent output="false">
        <cffunction name="getData"></cffunction>
      </cfcomponent>
      CFML
    instance.detect("Service.cfc", content).should be_false
  end
end
