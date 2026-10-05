require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

# Javalin, Micronaut and Quarkus are first-class on Kotlin, so their
# detectors read `.kt` sources as well as `.java` ones (#2856).
describe "Detect JVM frameworks in Kotlin sources" do
  options = create_test_options

  it "Javalin" do
    Detector::Java::Javalin.new(options).detect("App.kt", "import io.javalin.Javalin").should be_true
  end

  it "Micronaut" do
    Detector::Java::Micronaut.new(options).detect("BookController.kt", "import io.micronaut.http.annotation.Controller").should be_true
  end

  it "Quarkus" do
    Detector::Java::Quarkus.new(options).detect("Routes.kt", "import io.quarkus.vertx.web.Route").should be_true
  end

  it "not a Kotlin build script" do
    Detector::Java::Quarkus.new(options).detect("build.gradle.kts", "id(\"io.quarkus\")").should be_false
  end
end
