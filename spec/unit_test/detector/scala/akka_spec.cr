require "../../../spec_helper"
require "../../../../src/detector/detectors/scala/*"

describe "Detect Scala Akka" do
  options = create_test_options
  instance = Detector::Scala::Akka.new options

  it "test.scala with akka.http.scaladsl import" do
    instance.detect("test.scala", "import akka.http.scaladsl.server.Directives._").should be_true
  end

  it "test.scala with akka.http import" do
    instance.detect("test.scala", "import akka.http.scaladsl.Http").should be_true
  end

  it "test.scala with Apache Pekko HTTP import" do
    instance.detect("test.scala", "import org.apache.pekko.http.scaladsl.server.Directives._").should be_true
  end

  it "test.scala with Pekko actors only" do
    instance.detect("test.scala", "import org.apache.pekko.actor.typed.ActorSystem").should be_false
  end

  it "test.scala with a pekko.http config key only" do
    instance.detect("test.scala", %(ConfigFactory.parseString("pekko.http.server.idle-timeout = 5s"))).should be_false
  end

  it "test.scala without akka.http import" do
    instance.detect("test.scala", "import scala.concurrent.Future").should be_false
  end

  it "non-scala file with akka.http import" do
    instance.detect("test.java", "import akka.http.scaladsl.server.Directives._").should be_false
  end
end
