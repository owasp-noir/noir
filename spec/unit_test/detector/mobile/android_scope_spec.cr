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

  it "detects an embedded Ktor server living inside the Android source set" do
    # An Android app can bundle an on-device HTTP server whose routes
    # live under app/src/main/java/... — an incidental import would be
    # scoped out, but a real `routing { }` / `io.ktor.server` construct
    # must still surface (e.g. plain-app's local web server).
    root = File.tempname("noir-android-embedded")

    begin
      src = File.join(root, "app", "src", "main", "java", "com", "example", "web")
      FileUtils.mkdir_p(src)
      File.write(File.join(root, "app", "src", "main", "AndroidManifest.xml"), %(<manifest package="com.example.app"/>))
      File.write(
        File.join(src, "HttpModule.kt"),
        <<-KOTLIN
          package com.example.web
          import io.ktor.server.routing.routing
          import io.ktor.server.routing.get
          fun Application.httpModule() {
            routing {
              get("/health") { }
            }
          }
          KOTLIN
      )

      techs = detect_scope(root)
      techs.should contain("android")
      techs.should contain("kotlin_ktor")
    ensure
      cleanup_scope(root)
    end
  end

  it "does not treat an Android app's incidental Ktor client import as a server" do
    # `io.ktor.client.*` with no routing construct is just an HTTP
    # client — it must not flag the Android app as a Ktor server.
    root = File.tempname("noir-android-ktor-client")

    begin
      src = File.join(root, "app", "src", "main", "java", "com", "example", "net")
      FileUtils.mkdir_p(src)
      File.write(File.join(root, "app", "src", "main", "AndroidManifest.xml"), %(<manifest package="com.example.app"/>))
      File.write(
        File.join(src, "ApiClient.kt"),
        <<-KOTLIN
          package com.example.net
          import io.ktor.client.HttpClient
          import io.ktor.client.request.get
          suspend fun fetch(client: HttpClient) = client.get("https://example.com")
          KOTLIN
      )

      techs = detect_scope(root)
      techs.should contain("android")
      techs.should_not contain("kotlin_ktor")
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
