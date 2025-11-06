require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/models/logger.cr"
require "../../../src/models/code_locator.cr"
require "../../../src/models/file_helper.cr"

class TestHelper
  include FileHelper
end

describe "FileHelper" do
  before_each do
    # Reset CodeLocator for each test
    locator = CodeLocator.instance
    locator.clear_all
  end

  describe "get_all_files" do
    it "returns all files from CodeLocator" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.push("file_map", "/test/file1.cr")
      locator.push("file_map", "/test/file2.cr")

      files = helper.get_all_files
      files.should contain("/test/file1.cr")
      files.should contain("/test/file2.cr")
    end
  end

  describe "get_files_by_extension" do
    it "filters files by extension" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.push("file_map", "/test/file1.cr")
      locator.push("file_map", "/test/file2.rb")
      locator.push("file_map", "/test/file3.cr")

      cr_files = helper.get_files_by_extension(".cr")
      cr_files.size.should eq(2)
      cr_files.should contain("/test/file1.cr")
      cr_files.should contain("/test/file3.cr")
    end

    it "returns empty array if no matches" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.push("file_map", "/test/file1.cr")

      rb_files = helper.get_files_by_extension(".rb")
      rb_files.should be_empty
    end
  end

  describe "get_files_by_prefix" do
    it "filters files by prefix" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.push("file_map", "/app/src/file1.cr")
      locator.push("file_map", "/app/test/file2.cr")
      locator.push("file_map", "/lib/file3.cr")

      app_files = helper.get_files_by_prefix("/app")
      app_files.size.should eq(2)
      app_files.should contain("/app/src/file1.cr")
      app_files.should contain("/app/test/file2.cr")
    end
  end

  describe "get_files_by_prefix_and_extension" do
    it "filters by both prefix and extension" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.push("file_map", "/app/file1.cr")
      locator.push("file_map", "/app/file2.rb")
      locator.push("file_map", "/lib/file3.cr")

      files = helper.get_files_by_prefix_and_extension("/app", ".cr")
      files.size.should eq(1)
      files.should contain("/app/file1.cr")
    end
  end

  describe "get_public_files" do
    it "finds files in public directories" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.push("file_map", "/app/public/style.css")
      locator.push("file_map", "/app/public/script.js")
      locator.push("file_map", "/app/src/file.cr")

      public_files = helper.get_public_files("/app")
      public_files.size.should eq(2)
      public_files.should contain("/app/public/style.css")
      public_files.should contain("/app/public/script.js")
    end

    it "handles nested public directories" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.push("file_map", "/app/modules/admin/public/admin.css")
      locator.push("file_map", "/app/public/main.css")

      public_files = helper.get_public_files("/app")
      public_files.size.should eq(2)
    end

    it "returns empty array if no public files" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.push("file_map", "/app/src/file.cr")

      public_files = helper.get_public_files("/app")
      public_files.should be_empty
    end
  end

  describe "get_public_dir_files" do
    it "finds files in named directory with full path" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.push("file_map", "/app/assets/style.css")
      locator.push("file_map", "/app/assets/script.js")
      locator.push("file_map", "/app/src/file.cr")

      asset_files = helper.get_public_dir_files("/app", "assets")
      asset_files.size.should eq(2)
      asset_files.should contain("/app/assets/style.css")
      asset_files.should contain("/app/assets/script.js")
    end

    it "handles relative paths" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.push("file_map", "/app/static/images/logo.png")

      files = helper.get_public_dir_files("/app", "static/images")
      files.size.should eq(1)
      files.should contain("/app/static/images/logo.png")
    end

    it "handles absolute paths" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.push("file_map", "/var/www/assets/style.css")

      files = helper.get_public_dir_files("/var/www", "/var/www/assets")
      files.size.should eq(1)
      files.should contain("/var/www/assets/style.css")
    end

    it "matches folder name anywhere in path" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.push("file_map", "/app/modules/assets/file1.css")
      locator.push("file_map", "/lib/assets/file2.css")

      files = helper.get_public_dir_files("/app", "assets")
      files.size.should eq(2)
    end
  end
end
