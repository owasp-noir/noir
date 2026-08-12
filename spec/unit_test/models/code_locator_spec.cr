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

    locator.all_files.should contain("/tmp/noir-cache-spec-a.py")
    locator.content_for("/tmp/noir-cache-spec-a.py").should eq("print('hello')")
  end

  it "content_for returns nil for paths that were never registered" do
    locator = CodeLocator.new
    locator.content_for("/does/not/exist.rb").should be_nil
  end

  it "reset_files drops cached content" do
    locator = CodeLocator.new
    locator.register_file("/tmp/noir-cache-spec-b.py", "x = 1")
    locator.content_for("/tmp/noir-cache-spec-b.py").should_not be_nil

    locator.reset_files
    locator.content_for("/tmp/noir-cache-spec-b.py").should be_nil
    stats = locator.content_cache_stats
    stats[:bytes].should eq(0)
    stats[:files].should eq(0)
  end

  # The asymmetry `register_path` and `reset_files` replaced. It used to be a
  # string comparison behaving differently in `push` and `clear`, explained
  # only by a comment; registering a path must invalidate the derived views
  # without discarding content already read for other files.
  it "register_path invalidates the derived views but keeps cached content" do
    locator = CodeLocator.new
    locator.register_file("/tmp/noir-registry-spec.py", "x = 1")
    locator.files_by_extension(".py").should eq(["/tmp/noir-registry-spec.py"])

    locator.register_path("/tmp/noir-registry-spec-2.py")

    # Index rebuilt to include the new path...
    locator.files_by_extension(".py").sort.should eq(
      ["/tmp/noir-registry-spec-2.py", "/tmp/noir-registry-spec.py"])
    # ...and the first file's content survived.
    locator.content_for("/tmp/noir-registry-spec.py").should eq("x = 1")
    # The newly registered one has none, as documented.
    locator.content_for("/tmp/noir-registry-spec-2.py").should be_nil
  end

  it "all_files reports registrations in order and reset_files empties it" do
    locator = CodeLocator.new
    locator.register_path("/a.rb")
    locator.register_path("/b.rb")
    locator.all_files.should eq(["/a.rb", "/b.rb"])

    locator.reset_files
    locator.all_files.should be_empty
    locator.files_by_extension(".rb").should be_empty
  end

  # `reset_files` must not disturb the other 64 keys — the detector calls it
  # at the top of every scan, and the spec-format keys are drained later.
  it "reset_files leaves unrelated keys alone" do
    locator = CodeLocator.new
    locator.push("oas3-json", "/spec/openapi.json")
    locator.register_path("/a.rb")

    locator.reset_files

    locator.all_files.should be_empty
    locator.all("oas3-json").should eq(["/spec/openapi.json"])
  end

  it "stops caching once the total budget is exhausted" do
    ENV["NOIR_CONTENT_CACHE_MAX_MB"] = "0"
    begin
      locator = CodeLocator.new
      locator.register_file("/tmp/noir-cache-spec-c.py", "anything")
      # Budget is 0 bytes, so nothing gets cached, but the path still
      # makes it into file_map.
      locator.all_files.should contain("/tmp/noir-cache-spec-c.py")
      locator.content_for("/tmp/noir-cache-spec-c.py").should be_nil
    ensure
      ENV.delete("NOIR_CONTENT_CACHE_MAX_MB")
    end
  end

  it "saturates instead of overflowing on an absurd NOIR_CONTENT_CACHE_MAX_MB" do
    # Crystal checks integer arithmetic, so scaling the megabyte figure to
    # bytes *raised* rather than wrapping — the whole scan aborted with an
    # unhandled OverflowError stack trace before the first file was read.
    ENV["NOIR_CONTENT_CACHE_MAX_MB"] = "99999999999999"
    begin
      locator = CodeLocator.new
      locator.content_cache_stats[:budget].should eq(Int64::MAX)
      # A budget that large means "cache everything", so caching still works.
      locator.register_file("/tmp/noir-cache-spec-overflow.py", "content")
      locator.content_for("/tmp/noir-cache-spec-overflow.py").should eq("content")
    ensure
      ENV.delete("NOIR_CONTENT_CACHE_MAX_MB")
    end
  end

  it "still scales an ordinary NOIR_CONTENT_CACHE_MAX_MB to bytes" do
    ENV["NOIR_CONTENT_CACHE_MAX_MB"] = "8"
    begin
      CodeLocator.new.content_cache_stats[:budget].should eq(8_i64 * 1024 * 1024)
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
    locator.register_path("/a/urls.py")
    locator.register_path("/b/urls.py")
    locator.register_path("/c/views.py")

    locator.files_by_basename("urls.py").should eq(["/a/urls.py", "/b/urls.py"])
    locator.files_by_basename("views.py").should eq(["/c/views.py"])
    locator.files_by_basename("missing.py").should be_empty
  end

  # The index is built lazily and memoised, so a file_map that changes
  # after the first lookup must not keep serving the stale build.
  it "rebuilds after clear(\"file_map\")" do
    locator = CodeLocator.new
    locator.register_path("/a/urls.py")
    locator.files_by_basename("urls.py").should eq(["/a/urls.py"])

    locator.reset_files
    locator.files_by_basename("urls.py").should be_empty

    locator.register_path("/b/urls.py")
    locator.files_by_basename("urls.py").should eq(["/b/urls.py"])
  end

  it "rebuilds after clear_all" do
    locator = CodeLocator.new
    locator.register_path("/a/urls.py")
    locator.files_by_basename("urls.py").should eq(["/a/urls.py"])

    locator.clear_all
    locator.files_by_basename("urls.py").should be_empty
  end
end

describe "derived index invalidation" do
  it "does not serve a stale basename index after a later push" do
    locator = CodeLocator.new
    locator.register_path("/a/urls.py")
    locator.files_by_basename("urls.py").should eq(["/a/urls.py"])

    locator.register_path("/b/urls.py")
    locator.files_by_basename("urls.py").should eq(["/a/urls.py", "/b/urls.py"])
  end

  it "does not serve a stale extension index after a later push" do
    locator = CodeLocator.new
    locator.register_path("/a/one.py")
    locator.files_by_extension(".py").should eq(["/a/one.py"])

    locator.register_path("/b/two.py")
    locator.files_by_extension(".py").should eq(["/a/one.py", "/b/two.py"])
  end
end
