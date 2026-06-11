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
      files = locator.all("file_map")

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
      files = locator.all("file_map")

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
      files = locator.all("file_map")

      techs.should contain("postman")
      files.should contain(postman_json)
    ensure
      FileUtils.rm_rf(temp_dir) if temp_dir
      CodeLocator.instance.clear_all
    end
  end
end
