require "../../../spec_helper"
require "../../../../src/models/analyzer"
require "../../../../src/detector/detector"
require "file_utils"

describe "Detector Android source scope" do
  it "does not treat Android app source imports as server framework signals" do
    root = File.tempname("noir-android-scope")

    begin
      FileUtils.mkdir_p(File.join(root, "app", "src", "main", "java", "com", "example"))
      File.write(File.join(root, "app", "src", "main", "AndroidManifest.xml"), %(<manifest package="com.example.app"/>))
      File.write(
        File.join(root, "app", "src", "main", "java", "com", "example", "MainActivity.java"),
        "import org.springframework.boot.SpringApplication;"
      )

      techs = detect_scope(root)
      techs.should contain("android")
      techs.should_not contain("java_spring")
    ensure
      cleanup_scope(root)
    end
  end

  it "still detects a sibling server module in an Android monorepo" do
    root = File.tempname("noir-android-monorepo")

    begin
      FileUtils.mkdir_p(File.join(root, "app", "src", "main"))
      File.write(File.join(root, "app", "src", "main", "AndroidManifest.xml"), %(<manifest package="com.example.app"/>))

      FileUtils.mkdir_p(File.join(root, "server", "src", "main", "java", "com", "example"))
      File.write(
        File.join(root, "server", "src", "main", "java", "com", "example", "Application.java"),
        "import org.springframework.boot.SpringApplication;"
      )

      techs = detect_scope(root)
      techs.should contain("android")
      techs.should contain("java_spring")
    ensure
      cleanup_scope(root)
    end
  end
end

private def detect_scope(root : String) : Array(String)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  logger = NoirLogger.new(false, false, false, true)
  detected = detect_techs([root], options, [] of PassiveScan, logger)
  detected[0]
end

private def cleanup_scope(root : String)
  FileUtils.rm_rf(root) if Dir.exists?(root)
  CodeLocator.instance.clear("file_map")
  CodeLocator.instance.clear("android-manifest")
end
