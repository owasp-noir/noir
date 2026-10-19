require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Micronaut" do
  options = create_test_options
  instance = Detector::Java::Micronaut.new options

  it "java source importing io.micronaut" do
    instance.detect("Controller.java", "import io.micronaut.http.annotation.Controller;").should be_true
  end

  it "java source mentioning micronaut.io" do
    instance.detect("Controller.java", "// https://micronaut.io").should be_true
  end

  it "kotlin source importing io.micronaut" do
    instance.detect("Controller.kt", "import io.micronaut.http.annotation.Controller").should be_true
  end

  it "does not match pom.xml" do
    instance.detect("pom.xml", "<groupId>io.micronaut</groupId>").should be_false
  end

  it "does not match unrelated java source" do
    instance.detect("Controller.java", "import jakarta.ws.rs.Path;").should be_false
  end
end
