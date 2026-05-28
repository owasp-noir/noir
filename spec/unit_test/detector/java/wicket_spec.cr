require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Wicket" do
  options = create_test_options
  instance = Detector::Java::Wicket.new options

  it "pom.xml" do
    instance.detect("pom.xml", "org.apache.wicket:wicket-core").should be_true
  end

  it "build.gradle" do
    instance.detect("build.gradle", "implementation(\"org.apache.wicket:wicket-core:9.17.0\")").should be_true
  end

  it "java import" do
    instance.detect("Application.java", "import org.apache.wicket.protocol.http.WebApplication;").should be_true
  end

  it "mount path annotation" do
    instance.detect("ProductPage.java", "@MountPath(\"/products\")").should be_true
  end
end
