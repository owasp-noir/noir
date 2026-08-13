require "../../spec_helper"
require "../../../src/detector/detector"
require "../../../src/models/analyzer"
require "../../../src/models/locator_keys"
require "../../../src/models/noir"

# Two detect passes in one process, over two different trees.
#
# `detect_techs` used to clear six of the 64 locator keys by hand — the file
# registry and the five mobile ones. Every specification key survived into
# the next scan, so a process that runs two detect passes without a
# `clear_all` between them drained the *previous* codebase's spec files. The
# only thing masking it was the `File.exists?` guard in
# `SpecificationEngine#each_spec_file`, which passes whenever the first
# tree's files are still on disk — i.e. always, in the case that matters.
#
# That case is a library caller driving `detect_techs` / `analysis_endpoints`
# directly. The CLI never reached it: `--diff-path` is the only way to get
# two detect passes out of one `noir` process, and `src/cli/commands/scan.cr`
# has called `CodeLocator#clear_all` between the two halves since the flag
# was added. #2503's message and this comment both named diff mode anyway,
# which overstated the blast radius.
#
# A single-scan fixture sweep cannot see this by construction, which is why
# it survived long enough to have a comment written about it rather than a
# fix. This spec is the oracle: it fails with the hand-written clear list
# put back in place of `LocatorKeys.reset`.
describe "locator scan lifecycle" do
  it "does not carry a previous scan's spec registrations into the next" do
    logger = NoirLogger.new(false, false, false, true)
    oas3 = File.expand_path("#{__DIR__}/../../functional_test/fixtures/specification/oas3")
    har = File.expand_path("#{__DIR__}/../../functional_test/fixtures/specification/har")
    locator = CodeLocator.instance

    detect_techs([oas3], create_test_options, [] of PassiveScan, logger)
    locator.all(Noir::LocatorKeys::OAS3_JSON).should_not be_empty

    detect_techs([har], create_test_options, [] of PassiveScan, logger)

    locator.all(Noir::LocatorKeys::OAS3_JSON).should be_empty
    locator.all(Noir::LocatorKeys::HAR_PATH).should_not be_empty
    locator.all_files.any?(&.includes?("/specification/oas3/")).should be_false
  end
end

# The table-driven half: the spec above proves the bug is fixed for one key,
# this proves it stays fixed for all 63 and for every key added later.
describe "locator lifecycle reset" do
  it "clears exactly the keys a phase owns" do
    locator = CodeLocator.instance
    array_keys = Noir::LocatorKeys::ARRAY_KEYS
    single_keys = Noir::LocatorKeys::SINGLE_KEYS
    express = Noir::LocatorKeys::EXPRESS_ROUTER_PREFIX

    seed = -> do
      array_keys.each { |key| locator.push(key, "SENTINEL") }
      single_keys.each { |key| locator.set(key, "SENTINEL") }
      locator.push(express.key("/app.js"), "SENTINEL")
    end

    seed.call
    Noir::LocatorKeys.reset(Noir::LocatorKey::Lifecycle::DetectScoped)

    survivors = array_keys.select { |key| !key.lifecycle.detect_scoped? && locator.all(key).empty? }
    cleared = array_keys.select { |key| key.lifecycle.detect_scoped? && !locator.all(key).empty? }
    fail "detect-scoped keys the reset missed: #{cleared.map(&.name).sort!}" unless cleared.empty?
    fail "keys the reset cleared but does not own: #{survivors.map(&.name).sort!}" unless survivors.empty?
    single_keys.each do |key|
      locator.get(key).should be_nil if key.lifecycle.detect_scoped?
    end
    # The analyze-scoped namespace is untouched by a detect reset.
    locator.all(express.key("/app.js")).should eq ["SENTINEL"]

    Noir::LocatorKeys.reset(Noir::LocatorKey::Lifecycle::AnalyzeScoped)
    locator.all(express.key("/app.js")).should be_empty
  ensure
    CodeLocator.instance.clear_all
  end
end

# Run the full detect→analyze pipeline over `root` and deliberately leave the
# locator populated. `scan_base_path_spec.cr`'s helper clears on the way out,
# which would mask the carry-over these examples exist to catch.
private def scan_leaving_state(root : String) : Array(String)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints.map { |endpoint| "#{endpoint.method} #{endpoint.url}" }.sort!
end

# The endpoint-level companion to the two examples above.
#
# Those assert the locator *registration* is gone. This asserts what an
# embedder actually receives, which is the part that was user-visible: #2503's
# leak did not stop at the blackboard, it put the previous codebase's
# endpoints in the next scan's results.
#
# Both scans must detect the same tech or the example is vacuous. With
# oas3-then-har the second scan never runs the OAS3 analyzer at all, so the
# stale registrations go unread and it passes with or without the fix — two
# distinct OAS3 subtrees is what makes it bite. Verified against a build of
# #2503's parent, where the second scan returns 8 endpoints instead of 4, the
# extra four being scan 1's `/gems_json` and `/gems_yml`.
#
# Nothing else in the suite covers this. `--diff-path` cannot reach it —
# `src/cli/commands/scan.cr` calls `clear_all` between its two halves — and
# the fixture sweep runs one scan per process.
describe "locator scan lifecycle, end to end" do
  it "does not carry a previous scan's endpoints into the next" do
    locator = CodeLocator.instance
    # `clear_all` does not reset the scan roots, and this drives `NoirRunner`,
    # which publishes them. Restoring them is what keeps the example from
    # reintroducing the cross-file coupling #2492 removed.
    previous_bases = locator.scan_base_paths
    oas3 = File.expand_path("#{__DIR__}/../../functional_test/fixtures/specification/oas3")

    begin
      first = scan_leaving_state("#{oas3}/param_in_path")
      second = scan_leaving_state("#{oas3}/security_schemes")

      # What a fresh process reports for the same second tree.
      locator.clear_all
      locator.scan_base_paths = previous_bases
      expected = scan_leaving_state("#{oas3}/security_schemes")

      first.should_not be_empty
      expected.should_not be_empty
      second.should eq expected
    ensure
      locator.clear_all
      locator.scan_base_paths = previous_bases
    end
  end
end
