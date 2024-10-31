require "../../../../src/detector/detectors/*"

describe "Detect Java Armeria" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Java::Armeria.new options

  it "pom.xml" do
    instance.detect("pom.xml", "com.linecorp.armeria").should eq(true)
  end
  it "build.gradle" do
    instance.detect("build.gradle", "com.linecorp.armeria").should eq(true)
  end
end
