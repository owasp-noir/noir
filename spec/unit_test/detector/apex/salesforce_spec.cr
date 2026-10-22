require "../../../spec_helper"
require "../../../../src/detector/detectors/apex/*"

describe "Detect Apex Salesforce" do
  options = create_test_options
  instance = Detector::Apex::Salesforce.new options

  it "detects sfdx-project.json" do
    instance.detect("proj/sfdx-project.json", %({"packageDirectories": [{"path": "force-app"}]})).should be_true
  end

  it "detects an @RestResource class" do
    content = <<-APEX
      @RestResource(urlMapping='/Account/*')
      global with sharing class AccountRest {
          @HttpGet global static Account doGet() { return null; }
      }
      APEX
    instance.detect("classes/AccountRest.cls", content).should be_true
  end

  it "detects @AuraEnabled and webservice classes" do
    instance.detect("A.cls", "public class A { @AuraEnabled public static String x() { return ''; } }").should be_true
    instance.detect("B.cls", "global class B { webservice static Id y() { return null; } }").should be_true
  end

  it "ignores a LaTeX class file" do
    instance.detect("article.cls", "\\NeedsTeXFormat{LaTeX2e}\n\\ProvidesClass{article}\n\\LoadClass{report}").should be_false
  end

  it "ignores an Apex class without entry points" do
    instance.detect("Util.cls", "public class Util { public static Integer add(Integer a) { return a; } }").should be_false
  end

  it "ignores an unrelated sfdx-project.json" do
    instance.detect("sfdx-project.json", "{}").should be_false
  end
end
