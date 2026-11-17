require "../../spec_helper"
require "../../../src/analyzer/engines/java_engine"

private alias JavaEngine = Analyzer::Java::JavaEngine

private def declarations(source : String) : Hash(String, Array(String))
  JavaEngine.annotation_declarations(JavaEngine.strip_comments(source)).transform_values(&.to_a.sort)
end

describe "Analyzer::Java::JavaEngine.annotation_declarations" do
  {
    # source => {annotation type => annotations on it}
    %(@Target({ElementType.TYPE}) @Retention(RUNTIME) @Controller public @interface Api {}) => {"Api" => ["Controller", "Retention", "Target"]},
    %(@org.springframework.web.bind.annotation.RestController\n@interface Api {})           => {"Api" => ["RestController"]},
    %(@RequestMapping(path = ("/x" + "(y)"))\n@RestController\npublic @interface Api {})    => {"Api" => ["RequestMapping", "RestController"]},
    %(@Target(AnnotationTarget.CLASS)\n@Controller\nannotation class Api)                   => {"Api" => ["Controller", "Target"]},
    %(// @Controller\npublic @interface Plain {})                                           => {"Plain" => [] of String},
    %(@Controller\npublic class NotAnAnnotation {})                                         => {} of String => Array(String),
  }.each do |source, expected|
    it "reads #{source.lines.first}" do
      declarations(source).should eq(expected)
    end
  end
end

describe "Analyzer::Java::JavaEngine.controller_stereotypes" do
  it "adds the annotation types that carry a stereotype, however deep" do
    declared = {
      "Api"      => Set{"RestController"},
      "Realtime" => Set{"Api"},
      "Audited"  => Set{"Retention"},
    }
    stereotypes = JavaEngine.controller_stereotypes(declared)
    stereotypes.should contain("Api")
    stereotypes.should contain("Realtime")
    stereotypes.should_not contain("Audited")
    stereotypes.should contain("Controller")
  end
end
