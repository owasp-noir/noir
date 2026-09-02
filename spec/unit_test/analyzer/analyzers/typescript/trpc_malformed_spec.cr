require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/typescript/trpc"

# A malformed source file must cost the file, not the run.
#
# `each_top_level_kv` walks a router/procedure map body character by
# character and, whenever it meets something it cannot parse as `key:
# value`, hands the position to `skip_top_level_to_comma` and starts over.
# That helper stops *on* the character that ended the value — a top-level
# comma, or an unmatched closing bracket — so when the position it is given
# is already such a closer it returns the position unchanged and the
# `while` loop above it spins on that one character forever.
#
# Reaching it takes one brace too many, the shape a half-saved editor
# buffer or a truncated generated file has. Found by scanning a corpus of
# fixtures with random byte ranges cut out: a 55-byte `.ts` file hung the
# whole scan indefinitely — no output, no timeout, no exit code.
#
# The assertion is "returns", and the value of the spec is that it does so
# at all.
private def with_ts_file(content : String, &)
  dir = File.tempname("trpc_malformed_spec")
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

describe "malformed tRPC routers" do
  options = create_test_options

  it "terminates on a procedure map with an unmatched closing brace" do
    with_ts_file("const r = createRouter().mutation('add', { input: x},});\n") do |path|
      opts = options.dup
      opts["base"] = YAML::Any.new([YAML::Any.new(File.dirname(path))])
      Analyzer::Typescript::TRPC.new(opts).analyze
    end
  end

  it "terminates on a chain whose middle procedure was truncated" do
    source = <<-TS
      export const todoRouter = createRouter()
        .query('get', {
          input: z.object({ id: z.string() }),
        })
        .mutation('add', {
          input: sharedAddVali},
        })
        .mutation('delete', {
          input: z.object({ id: z.string() }),
        });
      TS

    with_ts_file(source) do |path|
      opts = options.dup
      opts["base"] = YAML::Any.new([YAML::Any.new(File.dirname(path))])
      Analyzer::Typescript::TRPC.new(opts).analyze
    end
  end

  it "still reads the routes of a well-formed router" do
    source = <<-TS
      import { router, publicProcedure } from './trpc';

      export const appRouter = router({
        listUsers: publicProcedure.query(() => []),
        createUser: publicProcedure.mutation(() => null),
      });
      TS

    with_ts_file(source) do |path|
      opts = options.dup
      opts["base"] = YAML::Any.new([YAML::Any.new(File.dirname(path))])
      urls = Analyzer::Typescript::TRPC.new(opts).analyze.map(&.url).sort!
      urls.should contain("/api/trpc/listUsers")
      urls.should contain("/api/trpc/createUser")
    end
  end
end
