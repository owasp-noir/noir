require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Vertx" do
  options = create_test_options
  instance = Detector::Java::Vertx.new options

  it "pom.xml" do
    instance.detect("pom.xml", "io.vertx").should be_true
  end

  it "build.gradle" do
    instance.detect("build.gradle", "io.vertx").should be_true
  end

  it "build.gradle.kts" do
    instance.detect("build.gradle.kts", "io.vertx").should be_true
  end

  it "settings.gradle.kts" do
    instance.detect("settings.gradle.kts", "io.vertx").should be_true
  end

  it "should not detect non-build files" do
    instance.detect("random.txt", "io.vertx").should be_false
  end

  it "should not detect build files without vertx dependency" do
    instance.detect("pom.xml", "some.other.dependency").should be_false
  end
end
