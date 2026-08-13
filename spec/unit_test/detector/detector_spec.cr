require "file_utils"
require "../../spec_helper"
require "../../../src/detector/detector"
require "../../../src/models/analyzer"
require "../../../src/models/code_locator"
require "../../../src/models/logger"

describe "detect_techs file walker" do
  it "prunes Xcode asset catalogs while keeping ordinary JSON and plist files" do
    temp_dir = File.tempname("noir_detector_xcassets")
    Dir.mkdir_p(temp_dir)

    begin
      info_plist = File.join(temp_dir, "Info.plist")
      config_json = File.join(temp_dir, "config.json")
      asset_json = File.join(temp_dir, "Assets.xcassets", "AppIcon.appiconset", "Contents.json")

      Dir.mkdir_p(File.dirname(asset_json))
      File.write(info_plist, <<-XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
          <key>CFBundleURLTypes</key>
          <array>
            <dict>
              <key>CFBundleURLSchemes</key>
              <array><string>sample</string></array>
            </dict>
          </array>
        </dict>
        </plist>
        XML
      File.write(config_json, %({"ordinary": true}))
      File.write(asset_json, %({"images": []}))

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      logger = NoirLogger.new(false, false, false, true)
      locator = CodeLocator.instance
      locator.clear_all

      detected = detect_techs([temp_dir], options, [] of PassiveScan, logger)
      techs = detected[0]
      files = locator.all_files

      techs.should contain("ios")
      files.should contain(info_plist)
      files.should contain(config_json)
      files.should_not contain(asset_json)
    ensure
      FileUtils.rm_rf(temp_dir) if temp_dir
      CodeLocator.instance.clear_all
    end
  end

  it "keeps named JSON config detectors behind the generic spec prefilter" do
    temp_dir = File.tempname("noir_detector_named_json")
    Dir.mkdir_p(temp_dir)

    begin
      vercel_json = File.join(temp_dir, "vercel.json")
      File.write(vercel_json, %({"version": 2}))

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      logger = NoirLogger.new(false, false, false, true)
      locator = CodeLocator.instance
      locator.clear_all

      detected = detect_techs([temp_dir], options, [] of PassiveScan, logger)
      techs = detected[0]
      files = locator.all_files

      techs.should contain("vercel")
      files.should contain(vercel_json)
    ensure
      FileUtils.rm_rf(temp_dir) if temp_dir
      CodeLocator.instance.clear_all
    end
  end

  it "keeps marked generic JSON specs behind the shared prefilter" do
    temp_dir = File.tempname("noir_detector_generic_json")
    Dir.mkdir_p(temp_dir)

    begin
      postman_json = File.join(temp_dir, "collection.json")
      File.write(postman_json, <<-JSON)
        {
          "info": {
            "name": "Example",
            "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
          },
          "item": []
        }
        JSON

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      logger = NoirLogger.new(false, false, false, true)
      locator = CodeLocator.instance
      locator.clear_all

      detected = detect_techs([temp_dir], options, [] of PassiveScan, logger)
      techs = detected[0]
      files = locator.all_files

      techs.should contain("postman")
      files.should contain(postman_json)
    ensure
      FileUtils.rm_rf(temp_dir) if temp_dir
      CodeLocator.instance.clear_all
    end
  end

  # A malformed glob makes `File.match?` raise inside the reader fiber.
  # Pre-fix the fiber died silently: the walk stopped where it was, the
  # remaining files were never read, and the caller saw an empty tech
  # list — a scan that looks "clean" but covered nothing, with exit 0.
  describe "malformed --exclude-path globs" do
    it "raises instead of silently abandoning the walk" do
      temp_dir = File.tempname("noir_detector_bad_glob")
      Dir.mkdir_p(temp_dir)

      begin
        File.write(File.join(temp_dir, "collection.json"), <<-JSON)
          {
            "info": {
              "name": "Example",
              "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            },
            "item": []
          }
          JSON

        options = create_test_options
        options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
        options["exclude_path"] = YAML::Any.new("[unterminated")
        logger = NoirLogger.new(false, false, false, true)
        CodeLocator.instance.clear_all

        expect_raises(Noir::InvalidExcludePathError, /invalid glob pattern/) do
          detect_techs([temp_dir], options, [] of PassiveScan, logger)
        end
      ensure
        FileUtils.rm_rf(temp_dir) if temp_dir
        CodeLocator.instance.clear_all
      end
    end

    # `File.match?` only raises once traversal reaches the malformed
    # part, so a pattern with a literal prefix stays dormant until the
    # walk descends into it — the partial-scan case.
    it "raises for a path-prefixed pattern that only fails deeper in the walk" do
      temp_dir = File.tempname("noir_detector_bad_glob_prefixed")
      Dir.mkdir_p(File.join(temp_dir, "src"))

      begin
        File.write(File.join(temp_dir, "src", "collection.json"), <<-JSON)
          {
            "info": {
              "name": "Example",
              "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            },
            "item": []
          }
          JSON

        options = create_test_options
        options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
        options["exclude_path"] = YAML::Any.new("src/[unterminated")
        logger = NoirLogger.new(false, false, false, true)
        CodeLocator.instance.clear_all

        expect_raises(Noir::InvalidExcludePathError, /invalid glob pattern/) do
          detect_techs([temp_dir], options, [] of PassiveScan, logger)
        end
      ensure
        FileUtils.rm_rf(temp_dir) if temp_dir
        CodeLocator.instance.clear_all
      end
    end

    it "still walks normally for a valid glob" do
      temp_dir = File.tempname("noir_detector_good_glob")
      Dir.mkdir_p(temp_dir)

      begin
        postman_json = File.join(temp_dir, "collection.json")
        File.write(postman_json, <<-JSON)
          {
            "info": {
              "name": "Example",
              "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            },
            "item": []
          }
          JSON

        options = create_test_options
        options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
        options["exclude_path"] = YAML::Any.new("*.md,src/[a-z]*.go")
        logger = NoirLogger.new(false, false, false, true)
        locator = CodeLocator.instance
        locator.clear_all

        detected = detect_techs([temp_dir], options, [] of PassiveScan, logger)

        detected[0].should contain("postman")
        locator.all_files.should contain(postman_json)
      ensure
        FileUtils.rm_rf(temp_dir) if temp_dir
        CodeLocator.instance.clear_all
      end
    end
  end

  # An unreadable file used to take the rest of its directory with it: the
  # per-file `TextFile.read` sat bare inside `Dir.each_child`, whose only
  # rescue is the directory-level one, so the raise unwound the whole
  # listing and every remaining sibling went unregistered — silently, exit 0.
  # Measured before the fix on a flat 501-file Gin tree: one `chmod 000`
  # file cut the scan from 501 endpoints to 277.
  #
  # Two unreadable files, deliberately: readdir order is not alphabetical
  # (and is hash-ordered on both APFS and ext4), so a single one could land
  # last by luck and the regression would not fire.
  it "loses only the unreadable files, not the rest of their directory" do
    temp_dir = File.tempname("noir_detector_unreadable")
    Dir.mkdir_p(temp_dir)
    # Resolved before the `begin` so `ensure` can restore the modes even if
    # creating them is what failed.
    unreadable = ["locked_a.go", "locked_b.go"].map { |name| File.join(temp_dir, name) }

    begin
      readable = (0...50).map do |i|
        path = File.join(temp_dir, "handler_#{i}.go")
        File.write(path, "package main\n\nfunc Handler#{i}() {}\n")
        path
      end

      unreadable.each do |path|
        File.write(path, "package main\n")
        File.chmod(path, 0o000)
      end

      # Mode bits do not apply to root, and a spec that cannot establish the
      # condition it tests must say so rather than pass. Probe by actually
      # reading: `File::Info#readable?` reports the mode bits, which for root
      # says "no" about a file root can in fact read.
      still_readable = unreadable.any? do |path|
        File.read(path)
        true
      rescue File::Error
        false
      end
      pending! "requires a non-root user: mode 000 is not enforced here" if still_readable

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      logger = NoirLogger.new(false, false, false, true)
      locator = CodeLocator.instance
      locator.clear_all

      detect_techs([temp_dir], options, [] of PassiveScan, logger)
      files = locator.all_files

      readable.each { |path| files.should contain(path) }
      unreadable.each { |path| files.should_not contain(path) }
    ensure
      unreadable.each { |path| File.chmod(path, 0o644) if File.exists?(path) }
      FileUtils.rm_rf(temp_dir) if temp_dir
      CodeLocator.instance.clear_all
    end
  end
end
