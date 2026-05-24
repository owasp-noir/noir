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
end
