require "../../spec_helper"
require "file_utils"
require "../../../src/cli/commands/cache"

# Each spec body that touches the cache filesystem state runs inside a
# disposable NOIR_HOME so concurrent runs (and earlier specs that may
# have left state) can't influence the assertions.
private def with_isolated_cache_dir(&)
  prev_home = ENV["NOIR_HOME"]?
  prev_disable = ENV["NOIR_CACHE_DISABLE"]?
  tmp = File.tempname("noir-cache-cli-spec")
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

describe Noir::CLI::CacheCommand do
  describe ".parse_argv" do
    it "treats no args as 'show help' (action nil, help false)" do
      parsed = Noir::CLI::CacheCommand.parse_argv([] of String)
      parsed.action.should be_nil
      parsed.rest.should be_empty
      parsed.help.should be_false
    end

    it "captures the first positional as the action" do
      parsed = Noir::CLI::CacheCommand.parse_argv(["info"])
      parsed.action.should eq("info")
      parsed.rest.should be_empty
    end

    it "collects extra positionals into rest in order" do
      parsed = Noir::CLI::CacheCommand.parse_argv(["purge", "7", "ignored"])
      parsed.action.should eq("purge")
      parsed.rest.should eq(["7", "ignored"])
    end

    it "sets help on -h / --help anywhere in argv" do
      Noir::CLI::CacheCommand.parse_argv(["-h"]).help.should be_true
      Noir::CLI::CacheCommand.parse_argv(["--help"]).help.should be_true
      Noir::CLI::CacheCommand.parse_argv(["purge", "--help"]).help.should be_true
    end
  end

  describe ".parse_days" do
    it "accepts positive integers" do
      Noir::CLI::CacheCommand.parse_days("1").should eq(1)
      Noir::CLI::CacheCommand.parse_days("365").should eq(365)
    end

    it "rejects zero" do
      # `purge_older_than(0)` would discard every entry — that's
      # `clear`'s job, not `purge`'s. Validation rejects it explicitly.
      Noir::CLI::CacheCommand.parse_days("0").should be_nil
    end

    it "rejects negative" do
      Noir::CLI::CacheCommand.parse_days("-5").should be_nil
    end

    it "rejects non-integer input" do
      Noir::CLI::CacheCommand.parse_days("foo").should be_nil
      Noir::CLI::CacheCommand.parse_days("3.5").should be_nil
      Noir::CLI::CacheCommand.parse_days("").should be_nil
    end

    it "returns nil for nil input" do
      Noir::CLI::CacheCommand.parse_days(nil).should be_nil
    end

    it "rejects values above the MAX_PURGE_DAYS bound (avoids Time overflow)" do
      # `Time.utc - <very-large>.days` raises ArgumentError because
      # the resulting Time falls outside Crystal's supported range.
      # Validation has to catch this before the arithmetic runs.
      Noir::CLI::CacheCommand.parse_days("99999999").should be_nil
      Noir::CLI::CacheCommand.parse_days("36501").should be_nil # one over the bound
    end

    it "accepts the MAX_PURGE_DAYS boundary value itself" do
      Noir::CLI::CacheCommand.parse_days(Noir::CLI::CacheCommand::MAX_PURGE_DAYS.to_s).should eq(Noir::CLI::CacheCommand::MAX_PURGE_DAYS)
    end
  end

  describe ".clear" do
    it "wipes every cache entry and reports the count" do
      with_isolated_cache_dir do |_|
        LLM::Cache.store("a", "1").should be_true
        LLM::Cache.store("b", "22").should be_true

        io = IO::Memory.new
        Noir::CLI::CacheCommand.clear(io)
        out = io.to_s

        out.should contain("Removed 2 cache entries")
        LLM::Cache.stats.entries.should eq(0)
      end
    end

    it "uses singular wording when exactly one entry is removed" do
      with_isolated_cache_dir do |_|
        LLM::Cache.store("only", "1").should be_true

        io = IO::Memory.new
        Noir::CLI::CacheCommand.clear(io)
        io.to_s.should contain("Removed 1 cache entry")
      end
    end

    it "reports zero entries cleanly when cache is already empty" do
      with_isolated_cache_dir do |_|
        io = IO::Memory.new
        Noir::CLI::CacheCommand.clear(io)
        io.to_s.should contain("Removed 0 cache entries")
      end
    end
  end

  describe ".purge" do
    it "removes only entries older than N days" do
      with_isolated_cache_dir do |_|
        LLM::Cache.store("old", "old-content").should be_true
        LLM::Cache.store("new", "new-content").should be_true
        old_path = LLM::Cache.path_for("old")
        File.touch(old_path, Time.utc - 10.days)

        io = IO::Memory.new
        Noir::CLI::CacheCommand.purge(["7"], io)
        out = io.to_s

        out.should contain("Purged 1 cache entry")
        out.should contain("older than 7 days")
        File.exists?(old_path).should be_false
        File.exists?(LLM::Cache.path_for("new")).should be_true
      end
    end

    it "uses singular 'day' when threshold is 1" do
      with_isolated_cache_dir do |_|
        io = IO::Memory.new
        Noir::CLI::CacheCommand.purge(["1"], io)
        io.to_s.should contain("older than 1 day")
      end
    end

    it "uses plural 'days' for any threshold other than 1" do
      with_isolated_cache_dir do |_|
        io = IO::Memory.new
        Noir::CLI::CacheCommand.purge(["30"], io)
        io.to_s.should contain("older than 30 days")
      end
    end
  end

  describe ".print_info" do
    it "shows zero-entry summary without oldest/newest lines" do
      with_isolated_cache_dir do |_|
        io = IO::Memory.new
        Noir::CLI::CacheCommand.print_info(io)
        out = io.to_s

        out.should contain("Entries:")
        out.should contain("Total size:")
        # No entries → no mtime block
        out.should_not contain("Oldest entry:")
        out.should_not contain("Newest entry:")
        # Footer hint must always print so users know how to disable
        out.should contain("--cache-disable")
        out.should contain("NOIR_CACHE_DISABLE=1")
      end
    end

    it "includes oldest and newest entry lines when entries > 0" do
      with_isolated_cache_dir do |_|
        LLM::Cache.store("entry", "x").should be_true

        io = IO::Memory.new
        Noir::CLI::CacheCommand.print_info(io)
        out = io.to_s

        out.should contain("Oldest entry:")
        out.should contain("Newest entry:")
        out.should match(/\d+[smhd] ago/)
      end
    end

    it "surfaces the NOIR_CACHE_DISABLE override when set" do
      with_isolated_cache_dir do |_|
        ENV["NOIR_CACHE_DISABLE"] = "1"
        io = IO::Memory.new
        Noir::CLI::CacheCommand.print_info(io)
        io.to_s.should contain("disabled via NOIR_CACHE_DISABLE")
      end
    end
  end

  describe ".print_help" do
    it "lists every supported action and the scan-time flags" do
      io = IO::Memory.new
      Noir::CLI::CacheCommand.print_help(io)
      out = io.to_s

      %w[info clear purge].each { |action| out.should contain(action) }
      out.should contain("SCAN-TIME FLAGS")
      out.should contain("--cache-disable")
      out.should contain("--cache-clear")
      out.should contain("NOIR_CACHE_DISABLE")
    end
  end
end
