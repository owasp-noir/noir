require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/typescript/trpc"

private def with_trpc_file(content : String, &)
  dir = File.tempname("trpc_schema_spec")
  Dir.mkdir_p(dir)
  path = File.join(dir, "router.ts")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear_all
  locator.register_file(path, content)
  begin
    yield path
  ensure
    locator.clear_all
    FileUtils.rm_rf(dir)
  end
end

describe "tRPC schema composite extraction" do
  options = create_test_options

  it "collects parameters from merge, union, extend, and, and discriminatedUnion" do
    content = <<-TS
      import { initTRPC } from '@trpc/server';
      import { z } from 'zod';

      const t = initTRPC.create();

      export const appRouter = t.router({
        merged: t.procedure
          .input(z.object({ a: z.string() }).merge(z.object({ b: z.number() })))
          .query(() => 1),
        unioned: t.procedure
          .input(z.union([z.object({ u1: z.string() }), z.object({ u2: z.number() })]))
          .query(() => 1),
        extended: t.procedure
          .input(z.object({ e1: z.string() }).extend({ e2: z.number() }))
          .query(() => 1),
        anded: t.procedure
          .input(z.object({ x: z.string(), shared: z.string() }).and(z.object({ y: z.number(), shared: z.number() })))
          .query(() => 1),
        discriminated: t.procedure
          .input(z.discriminatedUnion('kind', [
            z.object({ kind: z.literal('a'), d1: z.string() }),
            z.object({ kind: z.literal('b'), d2: z.number() }),
          ]))
          .query(() => 1),
      });
      TS

    with_trpc_file(content) do |path|
      opts = options.dup
      opts["base"] = YAML::Any.new([YAML::Any.new(File.dirname(path))])
      endpoints = Analyzer::Typescript::TRPC.new(opts).analyze

      merged = endpoints.find!(&.url.ends_with?("merged"))
      merged.params.map(&.name).should eq(["a", "b"])

      unioned = endpoints.find!(&.url.ends_with?("unioned"))
      unioned.params.map(&.name).should eq(["u1", "u2"])

      extended = endpoints.find!(&.url.ends_with?("extended"))
      extended.params.map(&.name).should eq(["e1", "e2"])

      anded = endpoints.find!(&.url.ends_with?("anded"))
      anded.params.map(&.name).should eq(["x", "shared", "y"])

      discriminated = endpoints.find!(&.url.ends_with?("discriminated"))
      discriminated.params.map(&.name).should eq(["kind", "d1", "d2"])
    end
  end

  it "collects composite schema parameters in v9 chain routers" do
    content = <<-TS
      import * as trpc from '@trpc/server';
      import { z } from 'zod';

      export const app = trpc.router()
        .query('comp', {
          input: z.object({ v1: z.string() }).merge(z.object({ v2: z.number() })),
          resolve() { return 1; },
        });
      TS

    with_trpc_file(content) do |path|
      opts = options.dup
      opts["base"] = YAML::Any.new([YAML::Any.new(File.dirname(path))])
      endpoints = Analyzer::Typescript::TRPC.new(opts).analyze

      comp = endpoints.find!(&.url.ends_with?("comp"))
      comp.params.map(&.name).should eq(["v1", "v2"])
    end
  end
end
