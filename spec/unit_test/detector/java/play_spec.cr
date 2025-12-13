require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Play" do
  options = create_test_options
  instance = Detector::Java::Play.new options

  it "routes file with Java-style route definitions (Integer type)" do
    instance.detect("routes", "GET /users controllers.Users.list(page: Integer)").should eq(true)
  end

  it "routes.conf file with Java-style route definitions (Boolean type)" do
    instance.detect("routes.conf", "POST /users/:id controllers.Users.update(id: Long, active: Boolean)").should eq(true)
  end

  it "java file with play.mvc.Controller import" do
    instance.detect("test.java", "import play.mvc.Controller;").should eq(true)
  end

  it "java file with play.mvc.Result import" do
    instance.detect("test.java", "import play.mvc.Result;").should eq(true)
  end

  it "java file with play.libs.Json import" do
    instance.detect("test.java", "import play.libs.Json;").should eq(true)
  end

  it "java file with play.routing import" do
    instance.detect("test.java", "import play.routing.*;").should eq(true)
  end

  it "java file without play imports" do
    instance.detect("test.java", "import java.util.*;").should eq(false)
  end

  it "non-java file with play import" do
    instance.detect("test.scala", "import play.mvc.Controller").should eq(false)
  end

  it "routes file without route definitions" do
    instance.detect("routes", "# Just comments").should eq(false)
  end
end
