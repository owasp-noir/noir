require "../../../spec_helper"
require "../../../../src/detector/detector"

# Javalin, Micronaut and Quarkus are first-class on Kotlin, so their
# detectors read `.kt` sources as well as `.java` ones (#2856).
describe "Detect JVM frameworks in Kotlin sources" do
  registry = build_detector_list(create_test_options).index_by(&.name)

  it "Javalin" do
    registry["java_javalin"].detect("App.kt", "import io.javalin.Javalin").should be_true
  end

  it "Micronaut" do
    registry["java_micronaut"].detect("BookController.kt", "import io.micronaut.http.annotation.Controller").should be_true
  end

  it "Quarkus" do
    registry["java_quarkus"].detect("Routes.kt", "import io.quarkus.vertx.web.Route").should be_true
  end

  it "not a Kotlin script that merely mentions Quarkus" do
    registry["java_quarkus"].detect("tasks.kts", "id(\"io.quarkus\")").should be_false
  end
end
