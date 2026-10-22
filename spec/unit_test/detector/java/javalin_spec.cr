require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Javalin" do
  options = create_test_options
  instance = Detector::Java::Javalin.new options

  it "java source importing io.javalin" do
    instance.detect("App.java", "import io.javalin.Javalin;").should be_true
  end

  it "kotlin source importing io.javalin" do
    instance.detect("App.kt", "import io.javalin.Javalin").should be_true
  end

  it "does not match pom.xml" do
    instance.detect("pom.xml", "<groupId>io.javalin</groupId>").should be_false
  end

  it "does not match unrelated java source" do
    instance.detect("App.java", "import java.util.List;").should be_false
  end
end
