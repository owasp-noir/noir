require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/javascript/nitro"

# Two Nitro apps under one scan base must both be reported.
#
# The analyzer's own dedup used to be `result.index { |e| e.url == url &&
# e.method == method }` — a lookup across the whole scan, with no notion of
# which app a route belonged to. `apps/a/routes/users.post.ts` and
# `apps/b/routes/users.post.ts` are both `POST /users`, so the second file
# read replaced the first outright: its params, its callees and its
# `code_path` all disappeared before the optimizer (which is where duplicate
# endpoints are supposed to be merged) ever saw them.
#
# And "second file read" is decided by which worker fiber finishes first, so
# on a large scan the surviving app flipped between runs of the identical
# input. That is how this was found: five `noir scan` runs over one corpus,
# diffing the JSON.

# The analyzer resolves its file set through `CodeLocator`, which the
# detection walk normally fills. These specs drive the analyzer directly, so
# they register the tree themselves.
private def register_tree(root : String) : Nil
  locator = CodeLocator.instance
  locator.clear_all
  Dir.glob(File.join(root, "**", "*")).each do |path|
    next unless File.file?(path)
    locator.register_file(path, File.read(path))
  end
end

describe "Nitro monorepo scoping" do
  it "keeps the same route from two Nitro apps" do
    temp_dir = File.tempname("noir_nitro_monorepo")

    begin
      ["a", "b"].each do |app|
        routes = File.join(temp_dir, "apps", app, "routes")
        Dir.mkdir_p(routes)
        File.write(File.join(temp_dir, "apps", app, "nitro.config.ts"), "export default {}\n")
        File.write(File.join(routes, "users.post.ts"), <<-TS)
          export default defineEventHandler(async (event) => {
            const body = await readBody(event)
            return body.#{app}Field
          })
          TS
      end

      register_tree(temp_dir)

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      endpoints = Analyzer::Javascript::Nitro.new(options).analyze

      users = endpoints.select { |e| e.url == "/users" && e.method == "POST" }
      users.size.should eq(2)

      paths = users.compact_map(&.details.code_paths.first?.try(&.path)).sort!
      paths.size.should eq(2)
      paths.first.should contain(File.join("apps", "a"))
      paths.last.should contain(File.join("apps", "b"))

      params = users.flat_map(&.params.map(&.name)).sort!
      params.should eq(["aField", "bField"])
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(temp_dir)
    end
  end

  # The precedence rule the global lookup was really there for, kept intact:
  # inside one app, `users.post.ts` still wins over the POST that a bare
  # `users.ts` implies, whichever order the two files are read in.
  it "still lets a method-specific file win inside one app" do
    temp_dir = File.tempname("noir_nitro_specific")
    routes = File.join(temp_dir, "routes")

    begin
      Dir.mkdir_p(routes)
      File.write(File.join(temp_dir, "nitro.config.ts"), "export default {}\n")
      File.write(File.join(routes, "users.ts"), <<-TS)
        export default defineEventHandler(async (event) => {
          const body = await readBody(event)
          return body.genericField
        })
        TS
      File.write(File.join(routes, "users.post.ts"), <<-TS)
        export default defineEventHandler(async (event) => {
          const body = await readBody(event)
          return body.specificField
        })
        TS

      register_tree(temp_dir)

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      endpoints = Analyzer::Javascript::Nitro.new(options).analyze

      posts = endpoints.select { |e| e.url == "/users" && e.method == "POST" }
      posts.size.should eq(1)
      posts.first.params.map(&.name).should eq(["specificField"])
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(temp_dir)
    end
  end
end
