require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/typescript/trpc"

# `extract_prefix` adopts a path-shaped `endpoint: '/x'` only from a file that
# mentions tRPC. That check must run once per file: run per `endpoint:` match
# it re-scanned the whole file for every row of a non-tRPC catalog, so 30,000
# rows (~2.4MB) cost 23s against 0.09s. The assertion is on the result, not on
# wall-clock time (timing is flaky on a loaded CI box); the 20,000-row input
# is what makes a per-match regression show up as a visibly stalled spec.
private ROUTER = <<-TS
  import { initTRPC } from '@trpc/server'
  const t = initTRPC.create()
  export const appRouter = t.router({ health: t.procedure.query(() => 'ok') })
  TS

private def scan_catalog(rows : String) : Array(Endpoint)
  dir = File.tempname("trpc_prefix_scaling")
  Dir.mkdir_p(dir)
  locator = CodeLocator.instance
  locator.clear_all
  {"router.ts" => ROUTER, "catalog.ts" => "export const catalog = [\n#{rows}];\n"}.each do |name, body|
    path = File.join(dir, name)
    File.write(path, body)
    locator.register_file(path, body)
  end
  opts = create_test_options
  opts["base"] = YAML::Any.new([YAML::Any.new(dir)])
  Analyzer::Typescript::TRPC.new(opts).analyze
ensure
  locator.try &.clear_all
  FileUtils.rm_rf(dir) if dir
end

describe "tRPC endpoint-prefix scan scaling" do
  it "ignores a large catalog of path-shaped `endpoint:` rows outside tRPC handlers" do
    rows = (1..20_000).join { |i| "  { endpoint: '/api/v1/items/#{i}' },\n" }

    # The catalog is not a tRPC handler, so it must not move the mount path.
    scan_catalog(rows).map(&.url).should eq(["/api/trpc/health"])
  end
end
