require "../../../spec_helper"
require "../../../../src/detector/detectors/cfml/*"

describe "Detect CFML FW/1" do
  options = create_test_options
  instance = Detector::Cfml::Fw1.new options

  it "detects an application extending framework.one" do
    content = <<-CFML
      component extends="framework.one" {
        this.name = "todoapp";
      }
      CFML
    instance.detect("Application.cfc", content).should be_true
  end

  it "detects the routes array" do
    content = <<-CFML
      component {
        variables.framework = {
          routes = [
            { "$GET/todo/:id" = "/main/get/id/:id" }
          ]
        };
      }
      CFML
    instance.detect("Application.cfc", content).should be_true
  end

  it "does not detect other extensions" do
    content = <<-CFML
      component extends="framework.one" {}
      CFML
    instance.detect("Application.cfm", content).should be_false
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
