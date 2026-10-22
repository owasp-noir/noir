require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Helidon MP" do
  options = create_test_options
  instance = Detector::Java::HelidonMp.new options

  it "Main.java" do
    instance.detect("Main.java", "import io.helidon.microprofile.server.Server;").should be_true
  end

  it "pom.xml" do
    instance.detect("pom.xml", "<artifactId>helidon-microprofile-core</artifactId>\n<groupId>io.helidon.microprofile.bundles</groupId>").should be_true
  end

  it "build.gradle" do
    instance.detect("build.gradle", "implementation 'io.helidon.microprofile.bundles:helidon-microprofile-core'").should be_true
  end

  it "plain JAX-RS resource without a Helidon import" do
    instance.detect("GreetResource.java", "import jakarta.ws.rs.Path;").should be_false
  end
end
