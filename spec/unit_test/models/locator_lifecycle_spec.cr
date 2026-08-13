require "../../spec_helper"
require "../../../src/detector/detector"
require "../../../src/models/analyzer"
require "../../../src/models/locator_keys"

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
