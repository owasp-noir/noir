require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# The Nuxt analyzer used to dedup routes inside `parallel_file_scan`: the first
# fiber to reach the mutex kept the endpoint and every later file for the same
# (url, method) was discarded whole. Because the loser never reached the
# optimizer, the deterministic sort there never saw it either, so a scan of the
# same tree emitted different `-f json` from run to run — which file:line and
# which params the duplicated route carried depended on fiber scheduling.
private def scan_nuxt(base : String, concurrency : String) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(base)])
  options["concurrency"] = YAML::Any.new(concurrency)
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.reset_files
end

# One `server/routes/auth.ts` per app, all resolving to `ANY /auth`. Enough of
# them that the workers genuinely interleave.
private def write_nuxt_apps(root : String, count : Int32) : Nil
  File.write(File.join(root, "package.json"), %({"private": true, "devDependencies": {"nuxt": "^3.11.0"}}))

  count.times do |i|
    app = File.join(root, "apps", "app#{i.to_s.rjust(3, '0')}")
    FileUtils.mkdir_p(File.join(app, "server", "routes"))
    File.write(File.join(app, "nuxt.config.ts"), "export default defineNuxtConfig({})\n")
    File.write(File.join(app, "server", "routes", "auth.ts"), <<-TS)
      export default defineEventHandler((event) => {
        return { session: getCookie(event, 'session_#{i}') }
      })
      TS
  end
end

describe "Nuxt route folding" do
  it "emits identical results across runs at the same concurrency" do
    fixture = "./spec/functional_test/fixtures/javascript/nuxtjs_monorepo"
    runs = Array.new(4) { scan_nuxt(fixture, "64").to_json }

    runs.uniq.size.should eq 1
  end

  it "emits identical results whatever the worker count" do
    # A single worker walks the tree in directory order; 64 workers do not. If
    # these two disagree, the analyzer is still resolving duplicates by
    # arrival order.
    fixture = "./spec/functional_test/fixtures/javascript/nuxtjs_monorepo"
    serial = scan_nuxt(fixture, "1").to_json
    parallel = scan_nuxt(fixture, "64").to_json

    parallel.should eq serial
  end

  it "keeps every duplicate route's inputs when many apps race" do
    root = File.tempname("noir-nuxt-fold")

    begin
      FileUtils.mkdir_p(root)
      write_nuxt_apps(root, 40)

      runs = Array.new(4) { scan_nuxt(root, "64").to_json }
      runs.uniq.size.should eq 1
      scan_nuxt(root, "1").to_json.should eq runs.first

      endpoints = scan_nuxt(root, "64")
      auth = endpoints.find { |endpoint| endpoint.url == "/auth" && endpoint.method == "ANY" } ||
             fail("MISSING ENDPOINT [ANY::/auth] for a 40-app Nuxt workspace")

      # Nothing is dropped: every app contributes its file and its cookie.
      auth.details.code_paths.size.should eq 40
      auth.params.map(&.name).sort!.should eq Array.new(40) { |i| "session_#{i}" }.sort!
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
