require "../../../spec_helper"
require "../../../../src/detector/detectors/scala/*"

describe "Detect Scala Scalatra" do
  options = create_test_options
  instance = Detector::Scala::Scalatra.new options

  it "test.scala with org.scalatra import" do
    instance.detect("test.scala", "import org.scalatra._").should eq(true)
  end

  it "test.scala with ScalatraServlet" do
    instance.detect("test.scala", "class MyServlet extends ScalatraServlet").should eq(true)
  end

  it "test.scala without scalatra import" do
    instance.detect("test.scala", "import scala.concurrent.Future").should eq(false)
  end

  it "non-scala file with scalatra import" do
    instance.detect("test.java", "import org.scalatra._").should eq(false)
  end
end
