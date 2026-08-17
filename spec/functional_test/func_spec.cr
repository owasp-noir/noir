require "spec" # Make spec DSL available
require "../../src/models/noir.cr"
require "../../src/models/endpoint.cr"
require "../../src/config_initializer.cr" # Added to define ConfigInitializer

module Noir
  {% unless Noir.has_constant?("VERSION") %}
    VERSION = "SPEC"
  {% end %}
end

# Drives one fixture through a real scan and asserts the endpoints it produced.
#
# ## Registration is side-effect free
#
# `test_detect` / `test_analyze` used to call `@app.detect` / `@app.analyze` in
# the method body — at spec *collection* time — and register `it` blocks that
# only asserted over the already-computed result. Two consequences, both
# measured:
#
#   * `--dry-run`, which executes no example bodies, still cost ~6.9s, and
#     `--example zzz_no_match` reported `0 examples` and still cost ~6.8s. No
#     filter could skip the scans, so there was no way to run one analyzer's
#     tester without running all 576.
#   * far worse: Crystal's runner is installed via `at_exit` and skips itself
#     when the process is already exiting on an error (`spec/dsl.cr:186`). A
#     single analyzer raising during collection therefore reported
#     `0 examples, 0 failures` and named nothing — 22k examples silently
#     replaced by a blank screen, which is exactly the failure a contributor
#     (or an agent) hits on a branch that broke one analyzer.
#
# The scan is now lazy: examples are registered from `@expected_endpoints`,
# which is known at collection time, and the first example to run triggers the
# scan. A raise surfaces as a normal failing example and every other tester
# still reports.
#
# ## The exception is memoized too
#
# `@scan_error` matters as much as `@scanned`. Marking the scan "done" and
# leaving a half-populated `@app` behind would turn one real error into one real
# error plus ~40 "expected endpoint not found" red herrings. Re-raising the
# stored exception makes every example in the tester name the actual cause.
class FunctionalTester
  # expected_count's symbols are:
  # :techs
  # :endpoints
  @expected_count : Hash(Symbol, Int32)
  @expected_endpoints : Array(Endpoint)
  @app : NoirRunner
  @path : String
  @scanned = false
  @scan_error : Exception? = nil

  def initialize(@path, expected_count, expected_endpoints, option_overrides : Hash(String, YAML::Any)? = nil)
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    noir_options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/#{@path}")])
    noir_options["nolog"] = YAML::Any.new(true)
    option_overrides.try &.each { |k, v| noir_options[k] = v }

    if !expected_count.nil?
      @expected_count = expected_count
    else
      @expected_count = Hash(Symbol, Int32).new
    end

    if !expected_endpoints.nil?
      @expected_endpoints = expected_endpoints
    else
      @expected_endpoints = Array(Endpoint).new
    end

    @app = NoirRunner.new noir_options
  end

  # Runs the scan once, on first use from inside an example.
  #
  # `CodeLocator` is a process-wide singleton, so it is reset here rather than
  # at registration: whichever tester runs first must not inherit the previous
  # one's file map. Crystal's spec runner is single-threaded, so no two
  # `ensure_scanned` calls interleave.
  private def ensure_scanned
    if error = @scan_error
      raise error
    end
    return if @scanned

    begin
      CodeLocator.instance.clear_all
      @app.detect
      @app.analyze
    rescue e
      @scan_error = e
      raise e
    ensure
      @scanned = true
    end
  end

  # The scanned runner. Reading it runs the scan; see `url=` for the pre-scan
  # configuration path, which must not.
  def app
    ensure_scanned
    @app
  end

  def endpoints : Array(Endpoint)
    app.endpoints
  end

  # Pre-scan configuration. Writes straight to `@app.options` — going through
  # `app` would run the scan and *then* change an option it had already read.
  #
  # The guard is the point: silently configuring a scan that already happened is
  # how a tester ends up asserting against a stale result.
  def url=(url)
    raise "FunctionalTester[#{@path}]: options changed after the scan already ran" if @scanned
    @app.options["url"] = YAML::Any.new(url)
  end

  # An expected endpoint's actual counterpart. "Not found" is an assertion
  # failure inside the example rather than a branch taken while registering
  # examples.
  #
  # Every example for a missing endpoint fails with the same greppable line, so
  # one absent endpoint is noisy (~1 failure per detail checked) but always names
  # the tester and the endpoint. The previous shape produced exactly one failure
  # here — and zero for a raising analyzer, which is the trade this makes.
  private def actual_endpoint(expected : Endpoint) : Endpoint
    key = "#{expected.method}::#{expected.url}"
    endpoints.find { |e| e.method == expected.method && e.url == expected.url } ||
      fail("MISSING ENDPOINT [#{key}] in tester: #{@path}")
  end

  private def actual_params(expected : Endpoint, name : String) : Array(Param)
    found = actual_endpoint(expected).params.select { |param| param.name == name }
    if found.empty?
      key = "#{expected.method}::#{expected.url}"
      fail("MISSING PARAM [#{name}] on [#{key}] in tester: #{@path}")
    end
    found
  end

  private def actual_callee(expected : Endpoint, name : String) : Callee
    key = "#{expected.method}::#{expected.url}"
    actual_endpoint(expected).callees.find { |callee| callee.name == name } ||
      fail("MISSING CALLEE [#{name}] on [#{key}] in tester: #{@path}")
  end

  def find_endpoint(key)
    @expected_endpoints.each do |endpoint|
      expected_key = endpoint.method.to_s + "::" + endpoint.url.to_s
      if expected_key.to_s == key.to_s
        return endpoint
      end
    end
    nil
  end

  def test_detect
    return unless @expected_count.has_key?(:techs)

    it "test detect using count check [#{@path}]" do
      app.techs.size.should eq @expected_count[:techs]
    end
  end

  def test_analyze
    if @expected_count.has_key?(:endpoints)
      it "test analyze using count check [#{@path}]" do
        endpoints.size.should eq @expected_count[:endpoints]
      end
    end

    @expected_endpoints.each do |expected|
      key = expected.method.to_s + "::" + expected.url.to_s

      describe "endpoint check [#{key}]" do
        it "check - url [K: #{key}]" do
          actual_endpoint(expected).url.should eq expected.url
        end

        it "check - method [K: #{key}]" do
          actual_endpoint(expected).method.should eq expected.method
        end

        if expected.protocol != "http"
          it "check - protocol [K: #{key}]" do
            actual_endpoint(expected).protocol.should eq expected.protocol
          end
        end

        if expected.params.size > 0
          describe "check - params" do
            expected.params.each do |param|
              it "check '#{param.name}' name " do
                actual_params(expected, param.name)[0].name.should eq param.name
              end

              it "check '#{param.name}' param_type '#{param.param_type}'" do
                actual_params(expected, param.name)
                  .any? { |found| found.param_type == param.param_type }
                  .should be_true
              end

              # `value` was never asserted at all, which is how a tester could
              # declare `Param.new("version", "null", "query")` and go green
              # while the emitted request really was `?version=null`. `value`
              # is what the curl / httpie / PowerShell builders put on the
              # wire and what the OAS builders publish as an `enum`, so a
              # wrong one is a wrong request, not cosmetics.
              #
              # Only a declared (non-empty) value is checked, because `""` is
              # this harness's established "not asserted" placeholder — most
              # testers spell it for params whose value is derived and long
              # (a GraphQL operation document, a JSON-RPC envelope). The other
              # half of the hole — an analyzer leaking source text into a
              # param the tester left blank — is covered precisely, and much
              # faster, by the unit specs for `PythonEngine#return_literal_value`
              # and `Noir::JvmLiteral.value_of`.
              if !param.value.empty?
                it "check '#{param.name}' value '#{param.value}'" do
                  actual_params(expected, param.name)
                    .select { |found| found.param_type == param.param_type }
                    .map(&.value)
                    .should contain param.value
                end
              end
            end
          end
        end

        if expected.callees.size > 0
          describe "check - callees" do
            expected.callees.each do |callee|
              it "check '#{callee.name}' name" do
                actual_callee(expected, callee.name).name.should eq callee.name
              end

              # Only compare the line when the spec author set one; most specs
              # only care about names, but Pyramid-style cases need to verify
              # def-line threading.
              if expected_line = callee.line
                it "check '#{callee.name}' line #{expected_line}" do
                  actual_callee(expected, callee.name).line.should eq expected_line
                end
              end

              if expected_path = callee.path
                it "check '#{callee.name}' path #{expected_path}" do
                  actual_path = actual_callee(expected, callee.name).path
                  actual_path.should_not be_nil
                  if actual_path
                    File.expand_path(actual_path).should eq File.expand_path(expected_path)
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def perform_tests
    test_detect
    test_analyze
  end
end
