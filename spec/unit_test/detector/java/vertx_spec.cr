require "../../../../src/detector/detectors/*"

describe "Detect Java Vertx" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Java::Vertx.new options

  it "pom.xml" do
    instance.detect("pom.xml", "io.vertx").should eq(true)
  end
  
  it "build.gradle" do
    instance.detect("build.gradle", "io.vertx").should eq(true)
  end
  
  it "build.gradle.kts" do
    instance.detect("build.gradle.kts", "io.vertx").should eq(true)
  end
  
  it "settings.gradle.kts" do
    instance.detect("settings.gradle.kts", "io.vertx").should eq(true)
  end
  
  it "should not detect non-build files" do
    instance.detect("random.txt", "io.vertx").should eq(false)
  end
  
  it "should not detect build files without vertx dependency" do
    instance.detect("pom.xml", "some.other.dependency").should eq(false)
  end
end