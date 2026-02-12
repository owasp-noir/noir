require "../../spec_helper"
require "../../../src/utils/passive_rules_updater.cr"
require "../../../src/models/logger.cr"
require "file_utils"

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
  end
end
