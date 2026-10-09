require "../../spec_helper"
require "../../../src/miniparsers/apex_extractor"

describe Noir::ApexExtractor do
  it "yields top-level members with annotations, args and lines, skipping inner classes" do
    source = <<-APEX
      /* 한글 주석 { */
      @RestResource(urlMapping='/x/*')
      global class Foo {
          String s = '}';
          @HttpPost
          global static String create(Map<String, Object> opts, List<Id> ids) {
              if (true) { return 'a'; }
          }
          public class Inner {
              @AuraEnabled public static void hidden(String y) {}
          }
          @AuraEnabled public String prop { get; set; }
      }
      APEX
    klass = Noir::ApexExtractor.parse(source).not_nil!
    klass.name.should eq "Foo"
    klass.annotations.should eq ["restresource"]
    klass.members.map { |m| {m.name, m.annotations, m.args, m.line} }.should eq [
      {"create", ["httppost"], ["opts", "ids"], 5},
    ]
  end

  it "returns nil when there is no class" do
    Noir::ApexExtractor.parse("public interface I { void x(); }").should be_nil
  end
end
