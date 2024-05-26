require "../../../src/detector/detectors/*"

describe "Detect Java Spring" do
  options = default_options()
  instance = DetectorJavaSpring.new options

  it "test.java" do
    instance.detect("test.java", "import org.springframework.boot.SpringApplication;").should eq(true)
  end
end
