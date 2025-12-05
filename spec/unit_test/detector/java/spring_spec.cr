require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Spring" do
  options = create_test_options
  instance = Detector::Java::Spring.new options

  it "test.java" do
    instance.detect("test.java", "import org.springframework.boot.SpringApplication;").should eq(true)
  end
end
