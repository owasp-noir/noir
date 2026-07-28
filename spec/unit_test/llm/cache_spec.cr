require "../../../src/llm/cache"
require "file_utils"
require "spec"

private def with_isolated_cache_dir(&)
  prev_home = ENV["NOIR_HOME"]?
  prev_disable = ENV["NOIR_CACHE_DISABLE"]?
  tmp = File.tempname("noir-cache-spec")
  Dir.mkdir_p(tmp)
  ENV["NOIR_HOME"] = tmp
  ENV.delete("NOIR_CACHE_DISABLE")
  begin
    LLM::Cache.enable
    yield tmp
  ensure
    if prev_home
      ENV["NOIR_HOME"] = prev_home
    else
      ENV.delete("NOIR_HOME")
    end
    if prev_disable
      ENV["NOIR_CACHE_DISABLE"] = prev_disable
    else
      ENV.delete("NOIR_CACHE_DISABLE")
    end
    FileUtils.rm_rf(tmp)
  end
end

describe LLM::Cache do
  describe ".key" do
    it "generates a deterministic SHA256 hash" do
      provider = "openai"
      model = "gpt-4o"
      kind = "ANALYZE"
      format = "json"
      payload = "some payload"

      # "openai|gpt-4o|ANALYZE|json|some payload"
      expected_hash = "236649cef258475a5d82d8519748c36ab49bf5bdf619c9f7b2e117a575fe08ac"

      key = LLM::Cache.key(provider, model, kind, format, payload)
      key.should eq(expected_hash)
    end

    it "produces different keys for different inputs" do
      k1 = LLM::Cache.key("p1", "m1", "k1", "f1", "payload")
      k2 = LLM::Cache.key("p1", "m1", "k1", "f1", "payload2")
      k1.should_not eq(k2)
    end
  end

  describe ".disabled_by_env?" do
    it "tolerates leading and trailing whitespace" do
      prev = ENV["NOIR_CACHE_DISABLE"]?
      begin
        ENV["NOIR_CACHE_DISABLE"] = "  true  "
        LLM::Cache.disabled_by_env?.should be_true
      ensure
        if prev
          ENV["NOIR_CACHE_DISABLE"] = prev
        else
          ENV.delete("NOIR_CACHE_DISABLE")
        end
      end
    end
  end

  describe ".store / .clear / .stats" do
    it "writes only .json files and bulk ops only touch them" do
      with_isolated_cache_dir do |home|
        cache_dir = File.join(home, "cache", "ai")
        LLM::Cache.store("abc", %({"ok":true})).should be_true
        # Drop a non-cache file in the same directory; it must survive
        # both clear and stats.
        FileUtils.mkdir_p(cache_dir)
        File.write(File.join(cache_dir, "user-dropped.txt"), "hello")

        stats = LLM::Cache.stats
        stats.entries.should eq(1)
        stats.bytes.should be > 0

        outcome = LLM::Cache.clear
        outcome.deleted.should eq(1)
        outcome.failed.should eq(0)
        File.exists?(File.join(cache_dir, "user-dropped.txt")).should be_true
      end
    end

    it "stats reports oldest and newest entry mtimes" do
      with_isolated_cache_dir do |_|
        LLM::Cache.store("a", "1").should be_true
        LLM::Cache.store("b", "22").should be_true
        stats = LLM::Cache.stats
        stats.entries.should eq(2)
        stats.oldest.should_not be_nil
        stats.newest.should_not be_nil
        # newest is at least as recent as oldest
        (stats.newest.not_nil! >= stats.oldest.not_nil!).should be_true
      end
    end
  end

  describe ".purge_older_than" do
    it "removes only entries older than the threshold" do
      with_isolated_cache_dir do |_|
        LLM::Cache.store("old", "old-content").should be_true
        LLM::Cache.store("new", "new-content").should be_true

        # Backdate the "old" entry by touching its mtime 10 days ago.
        old_path = LLM::Cache.path_for("old")
        ten_days_ago = Time.utc - 10.days
        File.touch(old_path, ten_days_ago)

        outcome = LLM::Cache.purge_older_than(7)
        outcome.deleted.should eq(1)
        outcome.failed.should eq(0)

        # New survives
        File.exists?(LLM::Cache.path_for("new")).should be_true
        File.exists?(old_path).should be_false
      end
    end

    it "returns zero deletes when nothing is old enough" do
      with_isolated_cache_dir do |_|
        LLM::Cache.store("fresh", "x").should be_true
        outcome = LLM::Cache.purge_older_than(7)
        outcome.deleted.should eq(0)
      end
    end
  end

  describe ".store atomicity" do
    it "leaves no .tmp residue on a successful write" do
      with_isolated_cache_dir do |home|
        cache_dir = File.join(home, "cache", "ai")
        LLM::Cache.store("k", "v").should be_true
        leftovers = Dir.children(cache_dir).select(&.includes?(".tmp-"))
        leftovers.should be_empty
      end
    end
  end

  # A crash between `File.write` and `File.rename` strands a temp file.
  # It doesn't end in `.json`, so it used to be invisible to every bulk
  # operation: `clear` couldn't delete it and `stats` didn't count its
  # bytes, leaving unreclaimable files in the cache directory.
  describe "stranded temp files" do
    it "recognizes the name shape `store` actually writes" do
      LLM::Cache.tmp_entry?("abc#{LLM::Cache::CACHE_FILE_SUFFIX}#{LLM::Cache::CACHE_TMP_MARKER}123-dead").should be_true
      LLM::Cache.tmp_entry?("abc.json").should be_false
      LLM::Cache.tmp_entry?("user-dropped.txt").should be_false
    end

    it "counts them in stats apart from usable entries" do
      with_isolated_cache_dir do |home|
        cache_dir = File.join(home, "cache", "ai")
        LLM::Cache.store("live", "12345").should be_true
        File.write(File.join(cache_dir, "orphan.json.tmp-99999-deadbeef"), "x" * 100)

        stats = LLM::Cache.stats
        stats.entries.should eq(1)
        stats.orphans.should eq(1)
        stats.orphan_bytes.should eq(100)
      end
    end

    it "is reclaimed by clear without inflating the entry count" do
      with_isolated_cache_dir do |home|
        cache_dir = File.join(home, "cache", "ai")
        LLM::Cache.store("live", "v").should be_true
        File.write(File.join(cache_dir, "orphan.json.tmp-99999-deadbeef"), "x")

        outcome = LLM::Cache.clear
        outcome.deleted.should eq(1)
        outcome.orphans.should eq(1)
        outcome.failed.should eq(0)
        Dir.children(cache_dir).should be_empty
      end
    end

    it "is purged on age like any other entry" do
      with_isolated_cache_dir do |home|
        cache_dir = File.join(home, "cache", "ai")
        stale = File.join(cache_dir, "orphan.json.tmp-99999-deadbeef")
        FileUtils.mkdir_p(cache_dir)
        File.write(stale, "x")
        File.touch(stale, Time.utc - 10.days)
        # An in-flight temp write from a concurrent process is seconds old,
        # so the age predicate must leave it alone.
        fresh = File.join(cache_dir, "inflight.json.tmp-88888-cafebabe")
        File.write(fresh, "y")

        outcome = LLM::Cache.purge_older_than(7)
        outcome.deleted.should eq(0)
        outcome.orphans.should eq(1)
        File.exists?(stale).should be_false
        File.exists?(fresh).should be_true
      end
    end
  end
end
