require "../../spec_helper"
require "../../../src/utils/passive_rules_updater.cr"
require "../../../src/models/logger.cr"
require "file_utils"

# Set up a disposable NOIR_HOME and (optionally) NOIR_BUNDLED_RULES_PATH
# so each spec sees a clean filesystem. The block receives both paths
# so the caller can seed either side of the user / bundled split.
private def with_isolated_rules_env(seed_bundled : Bool = false, &)
  prev_home = ENV["NOIR_HOME"]?
  prev_bundle = ENV["NOIR_BUNDLED_RULES_PATH"]?

  home = File.join(Dir.tempdir, "noir-rules-spec-home-#{Random.new.hex(4)}")
  bundle = File.join(Dir.tempdir, "noir-rules-spec-bundle-#{Random.new.hex(4)}")
  Dir.mkdir_p(home)
  if seed_bundled
    Dir.mkdir_p(bundle)
    File.write(File.join(bundle, "fixture.yaml"), "id: bundled-fixture\n")
  end

  ENV["NOIR_HOME"] = home
  ENV["NOIR_BUNDLED_RULES_PATH"] = bundle

  begin
    yield home, bundle
  ensure
    FileUtils.rm_rf(home)
    FileUtils.rm_rf(bundle)
    if prev_home
      ENV["NOIR_HOME"] = prev_home
    else
      ENV.delete("NOIR_HOME")
    end
    if prev_bundle
      ENV["NOIR_BUNDLED_RULES_PATH"] = prev_bundle
    else
      ENV.delete("NOIR_BUNDLED_RULES_PATH")
    end
  end
end

describe "PassiveRulesUpdater" do
  describe ".check_for_updates" do
    it "returns true when .revision file exists and not a git repo" do
      # Setup
      temp_home = File.join(Dir.tempdir, "noir_test_home_#{Random.new.hex(4)}")
      passive_rules_path = File.join(temp_home, "passive_rules")

      ENV["NOIR_HOME"] = temp_home

      begin
        FileUtils.mkdir_p(passive_rules_path)
        File.write(File.join(passive_rules_path, ".revision"), "v1.0.0")

        # Ensure it's not a git repo
        if Dir.exists?(File.join(passive_rules_path, ".git"))
          FileUtils.rm_rf(File.join(passive_rules_path, ".git"))
        end

        logger = NoirLogger.new(debug: true, verbose: false, colorize: false, no_log: true)

        # Execute
        result = PassiveRulesUpdater.check_for_updates(logger)

        # Verify
        result.should be_true
      ensure
        # Cleanup
        FileUtils.rm_rf(temp_home)
        ENV.delete("NOIR_HOME")
      end
    end

    it "short-circuits true on image-baked installs (user path empty, bundle present)" do
      with_isolated_rules_env(seed_bundled: true) do |_, _|
        logger = NoirLogger.new(debug: true, verbose: false, colorize: false, no_log: true)
        # Docker image case: no user rules, no git binary in the image,
        # but `/opt/noir/passive_rules` is populated. We must not try to
        # talk to upstream — there's nothing to compare against, and
        # auto_update would silently fail.
        PassiveRulesUpdater.check_for_updates(logger).should be_true
      end
    end
  end

  describe ".effective_rules_path" do
    it "prefers the user path when it has rules" do
      with_isolated_rules_env(seed_bundled: true) do |home, _|
        user_path = File.join(home, "passive_rules")
        Dir.mkdir_p(user_path)
        File.write(File.join(user_path, "user.yaml"), "id: user-rule\n")
        PassiveRulesUpdater.effective_rules_path.should eq(user_path)
      end
    end

    it "falls back to the bundled path when the user path is empty" do
      with_isolated_rules_env(seed_bundled: true) do |_, bundle|
        PassiveRulesUpdater.effective_rules_path.should eq(bundle)
      end
    end

    it "falls back to the bundled path when the user path doesn't exist" do
      with_isolated_rules_env(seed_bundled: true) do |home, bundle|
        # Explicitly remove the home dir so the user path doesn't even
        # exist (vs being empty); the resolution rule must still pick
        # the bundle.
        FileUtils.rm_rf(File.join(home, "passive_rules"))
        PassiveRulesUpdater.effective_rules_path.should eq(bundle)
      end
    end

    it "returns the user path when neither user nor bundled has rules" do
      with_isolated_rules_env(seed_bundled: false) do |home, _|
        # Bare install with no clone yet — caller's `initialize_rules`
        # is responsible for filling this in via git, but the resolver
        # still returns the canonical writable destination.
        PassiveRulesUpdater.effective_rules_path.should eq(File.join(home, "passive_rules"))
      end
    end
  end

  describe ".bundled_rules_available?" do
    it "is true when user is empty and bundled has rules" do
      with_isolated_rules_env(seed_bundled: true) do |_, _|
        PassiveRulesUpdater.bundled_rules_available?.should be_true
      end
    end

    it "is false when the user has rules of their own (user wins)" do
      with_isolated_rules_env(seed_bundled: true) do |home, _|
        user_path = File.join(home, "passive_rules")
        Dir.mkdir_p(user_path)
        File.write(File.join(user_path, "u.yaml"), "id: u\n")
        # Even with a populated bundle, the user-owned path takes
        # priority — `effective_rules_path` would return the user
        # path, so the bundle isn't "available" in the sense callers
        # care about.
        PassiveRulesUpdater.bundled_rules_available?.should be_false
      end
    end

    it "is false when nothing is bundled" do
      with_isolated_rules_env(seed_bundled: false) do |_, _|
        PassiveRulesUpdater.bundled_rules_available?.should be_false
      end
    end
  end

  describe ".initialize_rules" do
    it "skips the git-clone fallback when the image-baked ruleset is present" do
      with_isolated_rules_env(seed_bundled: true) do |home, _|
        logger = NoirLogger.new(debug: true, verbose: false, colorize: false, no_log: true)

        # Confirm precondition: user path is empty / missing.
        user_path = File.join(home, "passive_rules")
        (Dir.exists?(user_path) && !Dir.empty?(user_path)).should be_false

        PassiveRulesUpdater.initialize_rules(logger).should be_true

        # The whole point: we did NOT touch the user path with a
        # half-finished clone or an empty placeholder. The bundle is
        # serving from /opt and the home stays clean.
        (Dir.exists?(user_path) && !Dir.empty?(user_path)).should be_false
      end
    end
  end
end
