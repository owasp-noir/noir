require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Armeria" do
  options = create_test_options
  instance = Detector::Java::Armeria.new options

  it "pom.xml" do
    instance.detect("pom.xml", "com.linecorp.armeria").should eq(true)
  end
  it "build.gradle" do
    instance.detect("build.gradle", "com.linecorp.armeria").should eq(true)
  end
end
