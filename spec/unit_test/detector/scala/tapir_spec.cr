require "../../../spec_helper"
require "../../../../src/detector/detectors/scala/*"

describe "Detect Scala Tapir" do
  options = create_test_options
  instance = Detector::Scala::Tapir.new options

  it "test.scala with sttp.tapir import" do
    instance.detect("test.scala", "import sttp.tapir._").should be_true
  end

  it "test.scala with sttp.tapir.json import" do
    instance.detect("test.scala", "import sttp.tapir.json.circe._").should be_true
  end

  it "test.scala without tapir import" do
    instance.detect("test.scala", "import scala.concurrent.Future").should be_false
  end

  it "non-scala file with tapir import" do
    instance.detect("test.java", "import sttp.tapir._").should be_false
  end
end
