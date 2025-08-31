require "../../../../src/detector/detectors/*"

describe "Detect Kotlin Ktor" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Kotlin::Ktor.new options

  it "test.kt with ktor server import" do
    instance.detect("test.kt", "import io.ktor.server.application.*").should eq(true)
  end

  it "test.kt with ktor routing import" do
    instance.detect("test.kt", "import io.ktor.server.routing.*").should eq(true)
  end

  it "test.kt with ktor response import" do
    instance.detect("test.kt", "import io.ktor.server.response.*").should eq(true)
  end

  it "test.kt without ktor import" do
    instance.detect("test.kt", "import org.springframework.boot.SpringApplication").should eq(false)
  end

  it "non-kotlin file with ktor import" do
    instance.detect("test.java", "import io.ktor.server.application.*").should eq(false)
  end
end
