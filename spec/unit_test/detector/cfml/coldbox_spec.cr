require "../../../spec_helper"
require "../../../../src/detector/detectors/cfml/*"

describe "Detect CFML ColdBox" do
  options = create_test_options
  instance = Detector::Cfml::Coldbox.new options

  it "detects a Router.cfc by filename" do
    content = <<-CFML
      component {
        function configure() {
          route( "/", "main.index" );
        }
      }
      CFML
    instance.detect("config/Router.cfc", content).should be_true
  end

  it "detects the coldbox.system namespace" do
    content = <<-CFML
      component extends="coldbox.system.EventHandler" {
        function index( event, rc, prc ){}
      }
      CFML
    instance.detect("handlers/main.cfc", content).should be_true
  end

  it "detects a module config with an entry point" do
    content = <<-CFML
      component {
        this.title      = "api";
        this.entryPoint = "/api/v1";
      }
      CFML
    instance.detect("modules_app/api/ModuleConfig.cfc", content).should be_true
  end

  it "detects the legacy routes.cfm registration" do
    content = <<-CFML
      <cfset addRoute(":handler/:action?")>
      CFML
    instance.detect("config/routes.cfm", content).should be_true
  end

  it "does not detect unrelated CFML components" do
    content = <<-CFML
      <cfcomponent output="false">
        <cffunction name="getData" access="public"></cffunction>
      </cfcomponent>
      CFML
    instance.detect("Service.cfc", content).should be_false
  end
end
