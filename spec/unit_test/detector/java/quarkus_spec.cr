require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Quarkus" do
  options = create_test_options
  instance = Detector::Java::Quarkus.new options

  it "source importing Quarkus" do
    instance.detect("Routes.java", "import io.quarkus.vertx.web.Route;").should be_true
  end

  # The official starter's resource imports only `jakarta.ws.rs`; Quarkus
  # is named solely by its build manifest.
  it "pom.xml" do
    instance.detect("pom.xml", "<groupId>io.quarkus</groupId>\n<artifactId>quarkus-rest</artifactId>").should be_true
  end

  it "build.gradle.kts" do
    instance.detect("build.gradle.kts", "plugins {\n  java\n  id(\"io.quarkus\")\n}").should be_true
  end

  it "build.gradle" do
    instance.detect("build.gradle", "implementation 'io.quarkus:quarkus-rest'").should be_true
  end

  it "manifest without Quarkus" do
    instance.detect("pom.xml", "<groupId>org.springframework.boot</groupId>").should be_false
  end

  it "plain JAX-RS resource" do
    instance.detect("GreetingResource.java", "import jakarta.ws.rs.Path;").should be_false
  end
end
