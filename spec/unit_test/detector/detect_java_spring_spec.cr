require "../../../src/detector/detectors/*"

describe "Detect Java Spring" do
  options = default_options()
  instance = DetectorJavaSpring.new options

  it "pom.xml" do
    instance.detect("pom.xml", "org.springframework").should eq(true)
  end
  it "build.gradle" do
    instance.detect("build.gradle", "'org.springframework.boot' version '2.6.2'").should eq(true)
  end
end
