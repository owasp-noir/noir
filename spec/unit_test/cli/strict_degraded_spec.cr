require "file_utils"
require "../../spec_helper"
require "../../../src/cli/commands/scan"
require "../../../src/models/noir"
require "../../../src/models/code_locator"
require "../../../src/models/skipped_files"

# `--strict` is documented as "exit 2 if any analyzer failed or skipped a
# file". It was implemented as `!app.analyzer_failures.empty?` at a time when
# that list held tech-level analyzer failures and nothing else, so a scan that
# lost a whole subtree to an unlistable directory, dropped every symlinked
# package, exported nothing, or ran zero passive rules exited 0 and a CI gate
# built on it reported green.
#
# Two things are pinned here: that every phase's gaps reach the one list the
# exit code is derived from, and that the derivation itself is right.
private def runner_for(dir : String, **extra) : NoirRunner
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  extra.each { |key, value| options[key.to_s] = value }
  NoirRunner.new(options)
end

describe "strict-mode degraded detection" do
  before_each { Noir::SkippedFiles.clear }
  after_each do
    Noir::SkippedFiles.clear
    CodeLocator.instance.clear_all
  end

  # `-P` accepts any non-empty directory as a rules path, so a half-finished
  # clone or a mis-pointed `--passive-scan-path` makes the passive scan a
  # guaranteed false negative: zero rules produce zero findings, which is
  # exactly what a genuinely clean code base produces.
  it "reports a passive scan that ran with zero rules" do
    temp_dir = File.tempname("noir_zero_rules")
    rules_dir = File.tempname("noir_empty_rules")
    Dir.mkdir_p(temp_dir)
    Dir.mkdir_p(rules_dir)

    begin
      File.write(File.join(temp_dir, "Gemfile"), "gem 'sinatra'\n")
      File.write(File.join(temp_dir, "app.rb"), "require 'sinatra'\nget '/root' do\nend\n")
      File.write(File.join(rules_dir, "README.md"), "rules live here, eventually\n")

      app = runner_for(temp_dir,
        passive_scan: YAML::Any.new(true),
        passive_scan_no_update_check: YAML::Any.new(true),
        passive_scan_path: YAML::Any.new([YAML::Any.new(rules_dir)]),
        strict: YAML::Any.new(true))
      app.detect

      failures = app.analyzer_failures
      failures.size.should eq(1)
      failures.first.tech.should eq(Noir::SkippedFiles::PASSIVE_SCAN_SCOPE)
      failures.first.message.should contain("0 rules")

      Noir::CLI::ScanCommand.scan_exit_code(app, nil).should eq(2)
    ensure
      FileUtils.rm_rf(temp_dir)
      FileUtils.rm_rf(rules_dir)
    end
  end

  # The detection walk's gaps have to survive the analysis pass to be worth
  # anything: `analysis_endpoints` clears the channel at its top, and clearing
  # it wholesale would erase the walk's findings before the report read them.
  it "keeps a detection-phase gap through the analysis pass" do
    temp_dir = File.tempname("noir_strict_detect_gap")
    locked = File.join(temp_dir, "sub")
    Dir.mkdir_p(locked)

    begin
      File.write(File.join(temp_dir, "Gemfile"), "gem 'sinatra'\n")
      File.write(File.join(temp_dir, "app.rb"), "require 'sinatra'\nget '/root' do\nend\n")
      File.write(File.join(locked, "hidden.rb"), "require 'sinatra'\nget '/hidden' do\nend\n")
      File.chmod(locked, 0o000)

      still_listable = begin
        Dir.each_child(locked) { |_| break }
        true
      rescue File::Error
        false
      end
      pending! "requires a non-root user: mode 000 is not enforced here" if still_listable

      app = runner_for(temp_dir, strict: YAML::Any.new(true))
      app.detect
      app.analyze

      # The scan still produced its results — `--strict` flags a degraded
      # scan, it does not withhold what the scan found.
      app.endpoints.map(&.url).should eq(["/root"])

      failures = app.analyzer_failures
      failures.size.should eq(1)
      failures.first.tech.should eq(Noir::SkippedFiles::DETECT_SCOPE)
      Noir::CLI::ScanCommand.scan_exit_code(app, nil).should eq(2)
    ensure
      File.chmod(locked, 0o755) if File.exists?(locked)
      FileUtils.rm_rf(temp_dir)
    end
  end

  it "exits 0 on the same degraded scan when --strict was not asked for" do
    temp_dir = File.tempname("noir_nonstrict_gap")
    locked = File.join(temp_dir, "sub")
    Dir.mkdir_p(locked)

    begin
      File.write(File.join(temp_dir, "Gemfile"), "gem 'sinatra'\n")
      File.write(File.join(temp_dir, "app.rb"), "require 'sinatra'\nget '/root' do\nend\n")
      File.chmod(locked, 0o000)

      still_listable = begin
        Dir.each_child(locked) { |_| break }
        true
      rescue File::Error
        false
      end
      pending! "requires a non-root user: mode 000 is not enforced here" if still_listable

      app = runner_for(temp_dir)
      app.detect

      app.analyzer_failures.should_not be_empty
      Noir::CLI::ScanCommand.scan_exit_code(app, nil).should eq(0)
    ensure
      File.chmod(locked, 0o755) if File.exists?(locked)
      FileUtils.rm_rf(temp_dir)
    end
  end

  it "exits 0 on a clean --strict scan" do
    temp_dir = File.tempname("noir_clean_strict")
    Dir.mkdir_p(temp_dir)

    begin
      File.write(File.join(temp_dir, "Gemfile"), "gem 'sinatra'\n")
      File.write(File.join(temp_dir, "app.rb"), "require 'sinatra'\nget '/root' do\nend\n")

      app = runner_for(temp_dir, strict: YAML::Any.new(true))
      app.detect
      app.analyze

      app.analyzer_failures.should be_empty
      Noir::CLI::ScanCommand.scan_exit_code(app, nil).should eq(0)
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end
end
