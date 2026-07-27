require "../../spec_helper"
require "../../../src/utils/utils.cr"
require "../../../src/models/logger.cr"
require "../../../src/models/code_locator.cr"
require "../../../src/options.cr"

describe "Initialize" do
  locator = CodeLocator.new

  it "getter/setter - string" do
    locator.set "unittest", "abcd"
    locator.get("unittest").should eq("abcd")
  end

  it "all/push - array" do
    locator.push "unittest", "abcd"
    locator.push "unittest", "bbbb"
    locator.all("unittest").should eq(["abcd", "bbbb"])
  end
end

describe "content cache" do
  it "register_file pushes to file_map and caches content" do
    locator = CodeLocator.new
    locator.register_file("/tmp/noir-cache-spec-a.py", "print('hello')")

    locator.all("file_map").should contain("/tmp/noir-cache-spec-a.py")
    locator.content_for("/tmp/noir-cache-spec-a.py").should eq("print('hello')")
  end

  it "content_for returns nil for paths that were never registered" do
    locator = CodeLocator.new
    locator.content_for("/does/not/exist.rb").should be_nil
  end

  it "clear(\"file_map\") drops cached content" do
    locator = CodeLocator.new
    locator.register_file("/tmp/noir-cache-spec-b.py", "x = 1")
    locator.content_for("/tmp/noir-cache-spec-b.py").should_not be_nil

    locator.clear("file_map")
    locator.content_for("/tmp/noir-cache-spec-b.py").should be_nil
    stats = locator.content_cache_stats
    stats[:bytes].should eq(0)
    stats[:files].should eq(0)
  end

  it "stops caching once the total budget is exhausted" do
    ENV["NOIR_CONTENT_CACHE_MAX_MB"] = "0"
    begin
      locator = CodeLocator.new
      locator.register_file("/tmp/noir-cache-spec-c.py", "anything")
      # Budget is 0 bytes, so nothing gets cached, but the path still
      # makes it into file_map.
      locator.all("file_map").should contain("/tmp/noir-cache-spec-c.py")
      locator.content_for("/tmp/noir-cache-spec-c.py").should be_nil
    ensure
      ENV.delete("NOIR_CONTENT_CACHE_MAX_MB")
    end
  end

  it "honours NOIR_CONTENT_CACHE_DISABLE" do
    ENV["NOIR_CONTENT_CACHE_DISABLE"] = "true"
    begin
      locator = CodeLocator.new
      locator.register_file("/tmp/noir-cache-spec-d.py", "content")
      locator.content_for("/tmp/noir-cache-spec-d.py").should be_nil
      locator.content_cache_stats[:budget].should eq(0)
    ensure
      ENV.delete("NOIR_CONTENT_CACHE_DISABLE")
    end
  end
end

describe "basename index" do
  it "groups file_map entries by basename" do
    locator = CodeLocator.new
    locator.push("file_map", "/a/urls.py")
    locator.push("file_map", "/b/urls.py")
    locator.push("file_map", "/c/views.py")

    locator.files_by_basename("urls.py").should eq(["/a/urls.py", "/b/urls.py"])
    locator.files_by_basename("views.py").should eq(["/c/views.py"])
    locator.files_by_basename("missing.py").should be_empty
  end

  # The index is built lazily and memoised, so a file_map that changes
  # after the first lookup must not keep serving the stale build.
  it "rebuilds after clear(\"file_map\")" do
    locator = CodeLocator.new
    locator.push("file_map", "/a/urls.py")
    locator.files_by_basename("urls.py").should eq(["/a/urls.py"])

    locator.clear("file_map")
    locator.files_by_basename("urls.py").should be_empty

    locator.push("file_map", "/b/urls.py")
    locator.files_by_basename("urls.py").should eq(["/b/urls.py"])
  end

  it "rebuilds after clear_all" do
    locator = CodeLocator.new
    locator.push("file_map", "/a/urls.py")
    locator.files_by_basename("urls.py").should eq(["/a/urls.py"])

    locator.clear_all
    locator.files_by_basename("urls.py").should be_empty
  end
end

describe "derived index invalidation" do
  it "does not serve a stale basename index after a later push" do
    locator = CodeLocator.new
    locator.push("file_map", "/a/urls.py")
    locator.files_by_basename("urls.py").should eq(["/a/urls.py"])

    locator.push("file_map", "/b/urls.py")
    locator.files_by_basename("urls.py").should eq(["/a/urls.py", "/b/urls.py"])
  end

  it "does not serve a stale extension index after a later push" do
    locator = CodeLocator.new
    locator.push("file_map", "/a/one.py")
    locator.files_by_extension(".py").should eq(["/a/one.py"])

    locator.push("file_map", "/b/two.py")
    locator.files_by_extension(".py").should eq(["/a/one.py", "/b/two.py"])
  end
end
