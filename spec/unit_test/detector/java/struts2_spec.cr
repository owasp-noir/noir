require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Struts 2" do
  options = create_test_options
  instance = Detector::Java::Struts2.new options

  it "detects struts.xml packages" do
    instance.detect("struts.xml", %(<struts><package name="app" namespace="/app"/></struts>)).should be_true
  end

  it "detects Struts dispatcher in web.xml" do
    instance.detect("web.xml", "org.apache.struts2.dispatcher.filter.StrutsPrepareAndExecuteFilter").should be_true
  end

  it "detects Maven dependencies" do
    instance.detect("pom.xml", "<artifactId>struts2-convention-plugin</artifactId>").should be_true
  end

  it "detects Java Struts imports" do
    instance.detect("UserAction.java", "import org.apache.struts2.convention.annotation.Action;").should be_true
  end

  it "ignores unrelated Java files" do
    instance.detect("UserController.java", "import java.util.List;").should be_false
  end
end
