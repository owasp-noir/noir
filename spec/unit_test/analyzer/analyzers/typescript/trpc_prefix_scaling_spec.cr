require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/typescript/trpc"

# `extract_prefix` adopts a path-shaped `endpoint: '/x'` only from a file that
# mentions tRPC. That check must run once per file: run per `endpoint:` match
# it re-scanned the whole file for every row of a non-tRPC catalog, so 30,000
# rows (~2.4MB) cost 23s against 0.09s.
#
# The two catalogs below are the same size; only the path-shaped one reaches
# the mention gate (a `GET /…` label is rejected before it), so the pair
# measures the gate's cost against a free baseline.
private ROUTER = <<-TS
  import { initTRPC } from '@trpc/server'
  const t = initTRPC.create()
  export const appRouter = t.router({ health: t.procedure.query(() => 'ok') })
  TS

private def scan_catalog(rows : String) : Tuple(Array(Endpoint), Time::Span)
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
  endpoints = [] of Endpoint
  elapsed = Time.measure { endpoints = Analyzer::Typescript::TRPC.new(opts).analyze }
  {endpoints, elapsed}
ensure
  locator.try &.clear_all
  FileUtils.rm_rf(dir) if dir
end

describe "tRPC endpoint-prefix scan scaling" do
  it "gates path-shaped `endpoint:` rows on one tRPC mention check per file" do
    count = 20_000
    paths = (1..count).join { |i| "  { endpoint: '/api/v1/items/#{i}' },\n" }
    labels = (1..count).join { |i| "  { endpoint: 'GET /api/v1/items/#{i}' },\n" }

    label_eps, label_time = scan_catalog(labels)
    path_eps, path_time = scan_catalog(paths)

    # The catalog is not a tRPC handler, so it must not move the mount path.
    path_eps.map(&.url).should eq(label_eps.map(&.url))
    path_eps.map(&.url).should eq(["/api/trpc/health"])
    path_time.should be < (label_time * 3 + 1.second)
  end
end
