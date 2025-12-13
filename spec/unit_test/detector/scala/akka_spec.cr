require "../../../spec_helper"
require "../../../../src/detector/detectors/scala/*"

describe "Detect Scala Akka" do
  options = create_test_options
  instance = Detector::Scala::Akka.new options

  it "test.scala with akka.http.scaladsl import" do
    instance.detect("test.scala", "import akka.http.scaladsl.server.Directives._").should eq(true)
  end

  it "test.scala with akka.http import" do
    instance.detect("test.scala", "import akka.http.scaladsl.Http").should eq(true)
  end

  it "test.scala without akka.http import" do
    instance.detect("test.scala", "import scala.concurrent.Future").should eq(false)
  end

  it "non-scala file with akka.http import" do
    instance.detect("test.java", "import akka.http.scaladsl.server.Directives._").should eq(false)
  end
end
