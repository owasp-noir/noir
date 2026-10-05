require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"
require "file_utils"

describe "Detect Java JAX-RS" do
  options = create_test_options

  it "a .java resource" do
    instance = Detector::Java::JaxRs.new options
    instance.detect("/nowhere/UserResource.java", "import jakarta.ws.rs.Path;").should be_true
  end

  it "a .kt resource (#2856)" do
    instance = Detector::Java::JaxRs.new options
    instance.detect("/nowhere/UserResource.kt", "import jakarta.ws.rs.GET").should be_true
  end

  it "not a build manifest" do
    instance = Detector::Java::JaxRs.new options
    instance.detect("pom.xml", "<artifactId>jakarta.ws.rs-api</artifactId>").should be_false
  end

  it "not a file that names a derivative framework" do
    instance = Detector::Java::JaxRs.new options
    instance.detect("/nowhere/R.kt", "import jakarta.ws.rs.GET\nimport io.quarkus.runtime.Startup").should be_false
  end

  it "not a Kotlin module whose sibling source pulls in Quarkus" do
    root = File.tempname("noir_jaxrs_kotlin_derivative")
    source_dir = File.join(root, "src/main/kotlin/org/acme")
    Dir.mkdir_p(source_dir)
    File.write(File.join(source_dir, "Routes.kt"), "import io.quarkus.vertx.web.Route\n")
    resource = File.join(source_dir, "GreetingResource.kt")
    File.write(resource, "import jakarta.ws.rs.GET\n")

    begin
      instance = Detector::Java::JaxRs.new options
      instance.detect(resource, File.read(resource)).should be_false
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
