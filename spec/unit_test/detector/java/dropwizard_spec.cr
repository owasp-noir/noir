require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Dropwizard" do
  options = create_test_options
  instance = Detector::Java::Dropwizard.new options

  it "java source importing io.dropwizard" do
    instance.detect("App.java", "import io.dropwizard.core.Application;").should be_true
  end

  it "does not match pom.xml" do
    instance.detect("pom.xml", "<groupId>io.dropwizard</groupId>").should be_false
  end

  it "does not match unrelated java source" do
    instance.detect("App.java", "import jakarta.ws.rs.Path;").should be_false
  end
end
