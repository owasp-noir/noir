require "../../../spec_helper"
require "../../../../src/detector/detectors/scala/*"

describe "Detect Scala Finatra" do
  options = create_test_options
  instance = Detector::Scala::Finatra.new options

  it "scala file importing com.twitter.finatra.http" do
    instance.detect("UserController.scala", "import com.twitter.finatra.http.Controller").should be_true
  end

  it "build.sbt depending on finatra-http" do
    instance.detect("build.sbt", %(libraryDependencies += "com.twitter" %% "finatra-http-server" % "22.12.0")).should be_true
  end

  it "scala file using only finagle" do
    instance.detect("Main.scala", "import com.twitter.finagle.http.Request").should be_false
  end

  it "scalatra servlet" do
    instance.detect("Servlet.scala", "import org.scalatra._\nget(\"/x\") { }").should be_false
  end

  it "non-scala file with finatra import" do
    instance.detect("Main.java", "import com.twitter.finatra.http.Controller").should be_false
  end
end
