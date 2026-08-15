require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Helidon SE" do
  options = create_test_options
  instance = Detector::Java::HelidonSe.new options

  it "HttpService.java" do
    instance.detect("GreetService.java", "import io.helidon.webserver.http.HttpService;").should be_true
  end

  it "HttpRouting.java" do
    instance.detect("Main.java", "import io.helidon.webserver.http.HttpRouting;").should be_true
  end

  it "unrelated.java" do
    instance.detect("Application.java", "import org.springframework.boot.SpringApplication;").should be_false
  end

  it "non-java file" do
    instance.detect("pom.xml", "io.helidon.webserver").should be_false
  end
end
