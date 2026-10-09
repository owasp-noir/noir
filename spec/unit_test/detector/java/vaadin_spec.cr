require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Vaadin" do
  options = create_test_options
  instance = Detector::Java::Vaadin.new options

  it "pom.xml" do
    instance.detect("pom.xml", "<groupId>com.vaadin</groupId><artifactId>vaadin-spring-boot-starter</artifactId>").should be_true
  end

  it "build.gradle.kts" do
    instance.detect("build.gradle.kts", "implementation(\"com.vaadin:vaadin-core\")").should be_true
  end

  it "flow route import" do
    instance.detect("AdminView.java", "import com.vaadin.flow.router.Route;").should be_true
  end

  it "hilla import" do
    instance.detect("UserEndpoint.java", "import com.vaadin.hilla.BrowserCallable;").should be_true
    instance.detect("UserEndpoint.java", "import dev.hilla.Endpoint;").should be_true
  end

  it "unrelated java" do
    instance.detect("Health.java", "import org.springframework.boot.actuate.endpoint.annotation.Endpoint;").should be_false
  end
end
