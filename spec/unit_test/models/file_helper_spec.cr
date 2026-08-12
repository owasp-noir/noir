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

  describe "all_files" do
    it "returns all files from CodeLocator" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/test/file1.cr")
      locator.register_path("/test/file2.cr")

      files = helper.all_files
      files.should contain("/test/file1.cr")
      files.should contain("/test/file2.cr")
    end
  end

  describe "get_files_by_extension" do
    it "filters files by extension" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/test/file1.cr")
      locator.register_path("/test/file2.rb")
      locator.register_path("/test/file3.cr")

      cr_files = helper.get_files_by_extension(".cr")
      cr_files.size.should eq(2)
      cr_files.should contain("/test/file1.cr")
      cr_files.should contain("/test/file3.cr")
    end

    it "returns empty array if no matches" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/test/file1.cr")

      rb_files = helper.get_files_by_extension(".rb")
      rb_files.should be_empty
    end
  end

  describe "get_files_by_prefix" do
    it "filters files by prefix" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/src/file1.cr")
      locator.register_path("/app/test/file2.cr")
      locator.register_path("/lib/file3.cr")

      app_files = helper.get_files_by_prefix("/app")
      app_files.size.should eq(2)
      app_files.should contain("/app/src/file1.cr")
      app_files.should contain("/app/test/file2.cr")
    end

    it "does not match sibling paths with the same string prefix" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/src/file1.cr")
      locator.register_path("/app2/src/file2.cr")

      helper.get_files_by_prefix("/app").should eq(["/app/src/file1.cr"])
    end

    it "matches absolute files under the filesystem root prefix" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/src/file1.cr")

      helper.get_files_by_prefix(File::SEPARATOR.to_s).should eq(["/app/src/file1.cr"])
    end
  end

  describe "get_files_by_prefix_and_extension" do
    it "filters by both prefix and extension" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/file1.cr")
      locator.register_path("/app/file2.rb")
      locator.register_path("/lib/file3.cr")

      files = helper.get_files_by_prefix_and_extension("/app", ".cr")
      files.size.should eq(1)
      files.should contain("/app/file1.cr")
    end

    it "keeps extension filtering scoped to a path boundary" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/file1.cr")
      locator.register_path("/app2/file2.cr")

      helper.get_files_by_prefix_and_extension("/app", ".cr").should eq(["/app/file1.cr"])
    end
  end

  describe "get_public_files" do
    it "finds files in public directories that sit next to a shard.yml" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/shard.yml")
      locator.register_path("/app/public/style.css")
      locator.register_path("/app/public/script.js")
      locator.register_path("/app/src/file.cr")

      public_files = helper.get_public_files("/app")
      public_files.size.should eq(2)
      public_files.should contain("/app/public/style.css")
      public_files.should contain("/app/public/script.js")
    end

    it "handles nested public directories — each next to its own shard.yml" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/shard.yml")
      locator.register_path("/app/modules/admin/shard.yml")
      locator.register_path("/app/modules/admin/public/admin.css")
      locator.register_path("/app/public/main.css")

      public_files = helper.get_public_files("/app")
      public_files.size.should eq(2)
    end

    it "ignores public/ directories that are NOT siblings of a shard.yml" do
      # Regression for the docs-site false positive: a built static
      # site at `docs/public/` lives alongside a Crystal fixture but
      # doesn't itself have a shard.yml. Those files should not surface
      # as Crystal endpoints.
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/shard.yml")
      locator.register_path("/app/public/legitimate.css")  # under app/shard.yml — included
      locator.register_path("/app/docs/public/index.html") # no shard.yml in docs/ — skipped
      locator.register_path("/app/docs/public/sitemap.xml")
      locator.register_path("/app/docs/public/robots.txt")

      public_files = helper.get_public_files("/app")
      public_files.should eq(["/app/public/legitimate.css"])
    end

    it "does not include public files from sibling paths with the same string prefix" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/shard.yml")
      locator.register_path("/app/public/app.css")
      locator.register_path("/app2/shard.yml")
      locator.register_path("/app2/public/app2.css")

      helper.get_public_files("/app").should eq(["/app/public/app.css"])
    end

    it "returns empty array if no public files" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/shard.yml")
      locator.register_path("/app/src/file.cr")

      public_files = helper.get_public_files("/app")
      public_files.should be_empty
    end
  end

  describe "get_public_dir_files" do
    it "finds files in named directory with full path" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/assets/style.css")
      locator.register_path("/app/assets/script.js")
      locator.register_path("/app/src/file.cr")

      asset_files = helper.get_public_dir_files("/app", "assets")
      asset_files.size.should eq(2)
      asset_files.should contain("/app/assets/style.css")
      asset_files.should contain("/app/assets/script.js")
    end

    it "handles relative paths" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/static/images/logo.webp")

      files = helper.get_public_dir_files("/app", "static/images")
      files.size.should eq(1)
      files.should contain("/app/static/images/logo.webp")
    end

    it "handles absolute paths" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/var/www/assets/style.css")

      files = helper.get_public_dir_files("/var/www", "/var/www/assets")
      files.size.should eq(1)
      files.should contain("/var/www/assets/style.css")
    end

    it "matches folder name under the configured base path only" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/modules/assets/file1.css")
      locator.register_path("/lib/assets/file2.css")

      files = helper.get_public_dir_files("/app", "assets")
      files.should eq(["/app/modules/assets/file1.css"])
    end

    it "does not include named directories from sibling paths with the same string prefix" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/app/assets/file1.css")
      locator.register_path("/app2/assets/file2.css")

      helper.get_public_dir_files("/app", "assets").should eq(["/app/assets/file1.css"])
    end
  end

  describe "get_files_by_basename" do
    it "returns only files whose basename matches exactly" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/a/go.mod")
      locator.register_path("/b/nested/go.mod")
      locator.register_path("/c/go.sum")
      locator.register_path("/d/mygo.mod")

      helper.get_files_by_basename("go.mod").should eq(["/a/go.mod", "/b/nested/go.mod"])
    end

    it "returns an empty array when nothing matches" do
      TestHelper.new.get_files_by_basename("go.mod").should be_empty
    end
  end

  describe "get_files_by_relative_path" do
    # Stands in for `Dir.glob("<root>/**/<relative_path>")`, so the
    # multi-segment suffix has to match on a directory boundary and the
    # result has to stay inside the requested root.
    it "matches a multi-segment path suffix" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/repo/svc/myproj/urls.py")
      locator.register_path("/repo/other/urls.py")
      locator.register_path("/repo/svc/myproj/views.py")

      helper.get_files_by_relative_path("myproj/urls.py").should eq(["/repo/svc/myproj/urls.py"])
    end

    it "matches when the suffix sits directly under the root" do
      helper = TestHelper.new
      CodeLocator.instance.register_path("/repo/myproj/urls.py")

      helper.get_files_by_relative_path("myproj/urls.py", "/repo").should eq(["/repo/myproj/urls.py"])
    end

    it "excludes matches outside the requested root" do
      helper = TestHelper.new
      locator = CodeLocator.instance

      locator.register_path("/repo/a/myproj/urls.py")
      locator.register_path("/repo/b/myproj/urls.py")

      helper.get_files_by_relative_path("myproj/urls.py", "/repo/a").should eq(["/repo/a/myproj/urls.py"])
    end

    it "does not match a partial final segment" do
      helper = TestHelper.new
      # `Dir.glob` would not treat `notmyproj` as `myproj`; a bare
      # `ends_with?` without the separator would.
      CodeLocator.instance.register_path("/repo/notmyproj/urls.py")

      helper.get_files_by_relative_path("myproj/urls.py").should be_empty
    end

    it "returns an empty array for an empty relative path" do
      TestHelper.new.get_files_by_relative_path("").should be_empty
    end
  end
end
