require "../../../../src/detector/detectors/*"

describe "Detect Kotlin Spring" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Kotlin::Spring.new options

  it "test.kt" do
    instance.detect("test.kt", "import org.springframework.boot.SpringApplication").should eq(true)
  end
end
