require "../../../src/detector/detectors/*"

describe "Detect Java Spring" do
  options = default_options()
  instance = DetectorKotlinSpring.new options

  it "build.gradle.kts" do
    instance.detect("build.gradle.kts", "'org.springframework.boot' version '2.6.2'").should eq(true)
  end
end
