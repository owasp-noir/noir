require "../../../spec_helper"
require "../../../../src/detector/detectors/kotlin/*"

describe "Detect Kotlin Spring" do
  options = create_test_options
  instance = Detector::Kotlin::Spring.new options

  it "test.kt" do
    instance.detect("test.kt", "import org.springframework.boot.SpringApplication").should eq(true)
  end
end
