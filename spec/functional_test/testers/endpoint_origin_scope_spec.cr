require "../func_spec"
require "file_utils"

private def scan_origin_fixture(root : String) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.reset_files
end

private def rows_under(endpoints : Array(Endpoint), child : String)
  endpoints.compact_map do |endpoint|
    paths = endpoint.details.code_paths.select { |path| Noir::PathScope.under_root?(path.path, child) }
    next if paths.empty?
    {endpoint.method, endpoint.url, endpoint.protocol, endpoint.params.map { |p| {p.name, p.request_type} }.sort!,
     paths.map { |path| {path.path, path.line || 0} }.sort!}
  end.sort!
end

describe "endpoint origins across scan roots", tags: "functional" do
  it "returns the same rows from each mobile fixture as from its shared parent" do
    root = File.tempname("noir-origin-mobile")
    fixtures = File.expand_path("../fixtures/mobile", __DIR__)
    android = File.join(root, "android")
    ios = File.join(root, "ios")
    begin
      FileUtils.mkdir_p(root)
      FileUtils.cp_r(File.join(fixtures, "android"), android)
      FileUtils.cp_r(File.join(fixtures, "ios"), ios)
      parent = scan_origin_fixture(root)
      {android, ios}.each do |child|
        standalone = rows_under(scan_origin_fixture(child), child)
        standalone.should_not be_empty
        rows_under(parent, child).should eq(standalone)
      end
      parent.flat_map(&.details.origins).compact_map(&.platform).uniq!.sort!.should eq(["android", "ios"])
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "keeps a shared deep link on both platforms and preserves their build variants" do
    root = File.tempname("noir-origin-variants")
    android = File.join(root, "android")
    ios = File.join(root, "ios")
    begin
      {"main", "debug"}.each do |variant|
        dir = File.join(android, "src", variant)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "AndroidManifest.xml"), <<-XML)
          <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.example.app">
            <application><activity android:name=".Main" android:exported="true"><intent-filter>
              <action android:name="android.intent.action.VIEW"/>
              <category android:name="android.intent.category.BROWSABLE"/>
              <data android:scheme="shared" />
            </intent-filter></activity></application>
          </manifest>
          XML
      end
      File.write(File.join(android, "build.gradle"), "plugins { id 'com.android.application' }")
      FileUtils.mkdir_p(File.join(ios, "App.xcodeproj"))
      File.write(File.join(ios, "App.xcodeproj", "project.pbxproj"), "// test project")
      File.write(File.join(ios, "Info.plist"), <<-XML)
        <plist version="1.0"><dict>
          <key>CFBundleURLTypes</key><array><dict>
            <key>CFBundleURLSchemes</key><array><string>$(APP_SCHEME)</string></array>
          </dict></array>
        </dict></plist>
        XML
      File.write(File.join(ios, "Debug.xcconfig"), "APP_SCHEME = shared")
      File.write(File.join(ios, "Release.xcconfig"), "APP_SCHEME = shared")

      parent = scan_origin_fixture(root)
      shared = parent.select { |endpoint| endpoint.url == "shared://" }
      shared.size.should eq(4)
      shared.flat_map(&.details.origins).map { |o| {o.platform, o.variant || ""} }.sort_by! { |platform, variant| {platform || "", variant} }.should eq([
        {"android", ""}, {"android", "debug"}, {"ios", "Debug.xcconfig"}, {"ios", "Release.xcconfig"},
      ])
      options = create_test_options
      adb = OutputBuilderAdb.new(options)
      adb.io = IO::Memory.new
      adb.print(shared)
      commands = adb.io.to_s.lines
      commands.size.should eq(2)
      commands.all? { |command| command.includes?("'shared://'") && command.includes?("'com.example.app'") }.should be_true

      simctl = OutputBuilderSimctl.new(options)
      simctl.io = IO::Memory.new
      simctl.print(shared)
      simctl.io.to_s.lines.should eq(["xcrun simctl openurl booted 'shared://'"] * 2)

      {android, ios}.each do |child|
        rows_under(parent, child).should eq(rows_under(scan_origin_fixture(child), child))
      end
    ensure
      FileUtils.rm_rf(root)
    end
  end
  it "uses only each generated iOS app's configuration and preserves shared code routes" do
    root = File.tempname("noir-origin-generated-ios")
    begin
      {"alpha", "beta"}.each do |name|
        app = File.join(root, name)
        FileUtils.mkdir_p(app)
        File.write(File.join(app, "Info.plist"), <<-XML)
          <plist version="1.0"><dict>
            <key>CFBundleURLTypes</key><array><dict>
              <key>CFBundleURLSchemes</key><array><string>$(APP_SCHEME)</string><string>shared</string></array>
            </dict></array>
          </dict></plist>
          XML
        File.write(File.join(app, "Build.xcconfig"), "APP_SCHEME = #{name}")
        File.write(File.join(app, "Routes.swift"), %(let deepLink = "shared://open"))
      end

      parent = scan_origin_fixture(root)
      parent.count { |endpoint| endpoint.url == "shared://open" }.should eq(2)
      {"alpha", "beta"}.each do |name|
        child = File.join(root, name)
        standalone = rows_under(scan_origin_fixture(child), child)
        standalone.map(&.[1]).should contain("#{name}://")
        rows_under(parent, child).should eq(standalone)
      end
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
