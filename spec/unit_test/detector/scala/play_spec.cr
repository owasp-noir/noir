require "../../../spec_helper"
require "../../../../src/detector/detectors/scala/*"

describe "Detect Scala Play" do
  options = create_test_options
  instance = Detector::Scala::Play.new options

  it "routes file with Scala-style route definitions (Option type)" do
    instance.detect("routes", "GET /users controllers.Users.list(page: Option[Int])").should be_true
  end

  it "routes.conf file with Scala-style route definitions (optional param)" do
    instance.detect("routes.conf", "POST /users/:id controllers.Users.update(id: Long, name: String ?= \"default\")").should be_true
  end

  it "scala file with play.api.mvc import" do
    instance.detect("test.scala", "import play.api.mvc._").should be_true
  end

  it "scala file with BaseController" do
    instance.detect("test.scala", "class Users extends BaseController").should be_true
  end

  it "scala file with AbstractController" do
    instance.detect("test.scala", "class Users extends AbstractController").should be_true
  end

  it "scala file with play.api.routing import" do
    instance.detect("test.scala", "import play.api.routing.Router").should be_true
  end

  it "scala file without play imports" do
    instance.detect("test.scala", "import scala.concurrent.Future").should be_false
  end

  it "non-scala file with play import" do
    instance.detect("test.java", "import play.api.mvc._").should be_false
  end

  it "routes file without route definitions" do
    instance.detect("routes", "# Just comments").should be_false
  end
end
