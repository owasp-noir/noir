require "../../../src/detector/detectors/*"

describe "Detect Kotlin Spring" do
  options = default_options()
  instance = DetectorKotlinSpring.new options

  it "test.kt" do
    instance.detect("test.kt", "import org.springframework.boot.SpringApplication").should eq(true)
  end
end
