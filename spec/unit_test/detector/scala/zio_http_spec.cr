require "../../../spec_helper"
require "../../../../src/detector/detectors/scala/*"

describe "Detect Scala ZIO HTTP" do
  options = create_test_options
  instance = Detector::Scala::ZioHttp.new options

  it "test.scala with zio.http import" do
    instance.detect("test.scala", "import zio.http._").should be_true
  end

  it "test.scala with zio.http.Routes reference" do
    instance.detect("test.scala", "val routes = Routes(Method.GET / \"x\" -> handler(zio.http.Response.ok))").should be_true
  end

  it "test.scala without zio.http import" do
    instance.detect("test.scala", "import scala.concurrent.Future").should be_false
  end

  it "non-scala file with zio.http import" do
    instance.detect("test.java", "import zio.http._").should be_false
  end
end
