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

describe "Analyzer::Java::JavaEngine.inert_annotations" do
  it "adds the declared types whose annotations are all inert, however deep" do
    declared = {
      "Api"      => Set{"RestController"},
      "Realtime" => Set{"Api"},
      "Audited"  => Set{"Retention"},
      "Tracked"  => Set{"Audited", "Documented"},
      "Branded"  => Set{"Retention", "CompanyController"},
    }
    inert = JavaEngine.inert_annotations(declared)
    inert.should contain("Audited")
    inert.should contain("Tracked")
    inert.should contain("Component")
    # A stereotype, a type that carries one, and one that carries an
    # annotation from outside the scan may each make a controller.
    {"Controller", "RestController", "Api", "Realtime", "Branded", "CompanyController"}.each do |name|
      inert.should_not contain(name)
    end
  end
end
