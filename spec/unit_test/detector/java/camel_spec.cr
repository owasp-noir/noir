require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Apache Camel" do
  options = create_test_options
  instance = Detector::Java::Camel.new options

  it "RouteBuilder import" do
    instance.detect("RestRoutes.java", "import org.apache.camel.builder.RouteBuilder;").should be_true
  end
  it "camel dependency in pom.xml" do
    instance.detect("pom.xml", "<dependency><groupId>org.apache.camel</groupId></dependency>").should be_true
  end
  it "camel dependency in build.gradle.kts" do
    instance.detect("build.gradle.kts", "implementation(\"org.apache.camel:camel-core:4.4.0\")").should be_true
  end
  it "XML DSL with the camel namespace" do
    instance.detect("routes.xml", "<routes xmlns=\"http://camel.apache.org/schema/spring\"><rest path=\"/x\"/></routes>").should be_true
  end
  it "YAML DSL rest definition" do
    instance.detect("routes.camel.yaml", "- rest:\n    path: /x\n").should be_true
  end
  it "unrelated Java file" do
    instance.detect("App.java", "import org.springframework.web.bind.annotation.RestController;").should be_false
  end
  it "unrelated XML file" do
    instance.detect("web.xml", "<web-app><servlet-mapping/></web-app>").should be_false
  end
  it "unrelated YAML mapping" do
    instance.detect("application.yml", "server:\n  port: 8080\nrest:\n  path: /x\n").should be_false
  end
end
