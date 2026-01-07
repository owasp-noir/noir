require "../../../spec_helper"
require "../../../../src/detector/detectors/kotlin/*"

describe "Detect Kotlin Ktor" do
  options = create_test_options
  instance = Detector::Kotlin::Ktor.new options

  it "test.kt with ktor server import" do
    instance.detect("test.kt", "import io.ktor.server.application.*").should be_true
  end

  it "test.kt with ktor routing import" do
    instance.detect("test.kt", "import io.ktor.server.routing.*").should be_true
  end

  it "test.kt with ktor response import" do
    instance.detect("test.kt", "import io.ktor.server.response.*").should be_true
  end

  it "test.kt without ktor import" do
    instance.detect("test.kt", "import org.springframework.boot.SpringApplication").should be_false
  end

  it "non-kotlin file with ktor import" do
    instance.detect("test.java", "import io.ktor.server.application.*").should be_false
  end
end
