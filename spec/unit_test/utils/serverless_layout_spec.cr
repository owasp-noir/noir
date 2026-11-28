require "spec"
require "file_utils"
require "../../../src/utils/serverless_layout"

private def with_layout_dir(&)
  root = File.tempname("noir-serverless-layout-spec-")
  Dir.mkdir_p(root)
  begin
    yield root
  ensure
    FileUtils.rm_rf(root)
  end
end

private def touch(*parts : String, content : String = "") : String
  path = File.join(*parts)
  Dir.mkdir_p(File.dirname(path))
  File.write(path, content)
  path
end

describe Noir::ServerlessLayout do
  describe ".routing_remainder" do
    it "takes a routing dir at the scan root without a project marker" do
      with_layout_dir do |root|
        path = touch(root, "api", "users.ts")
        Noir::ServerlessLayout.routing_remainder(path, "/api/users.ts", "api").should eq({root, ["users.ts"]})
      end
    end

    it "keeps every segment below the routing dir" do
      with_layout_dir do |root|
        path = touch(root, "api", "users", "[id].ts")
        Noir::ServerlessLayout.routing_remainder(path, "/api/users/[id].ts", "api").should eq({root, ["users", "[id].ts"]})
      end
    end

    it "takes a nested routing dir only when its parent is a project root" do
      with_layout_dir do |root|
        path = touch(root, "apps", "web", "api", "users.ts")
        relative = "/apps/web/api/users.ts"
        Noir::ServerlessLayout.routing_remainder(path, relative, "api").should be_nil

        touch(root, "apps", "web", "package.json", content: "{}")
        Noir::ServerlessLayout.routing_remainder(path, relative, "api").should eq({File.join(root, "apps", "web"), ["users.ts"]})
      end
    end

    # Next.js `src/pages/api/` is not a Vercel `api/` dir: the marker sits in
    # the project root, two levels above `pages`.
    it "does not take a routing dir whose parent only has a project root above it" do
      with_layout_dir do |root|
        touch(root, "package.json", content: "{}")
        path = touch(root, "src", "pages", "api", "x.ts")
        Noir::ServerlessLayout.routing_remainder(path, "/src/pages/api/x.ts", "api").should be_nil
      end
    end

    it "moves on to a later routing dir when an earlier one is not anchored" do
      with_layout_dir do |root|
        touch(root, "lib", "api", "web", "vercel.json", content: "{}")
        path = touch(root, "lib", "api", "web", "api", "x.ts")
        Noir::ServerlessLayout.routing_remainder(path, "/lib/api/web/api/x.ts", "api").should eq({File.join(root, "lib", "api", "web"), ["x.ts"]})
      end
    end

    it "takes the first routing dir when the name repeats" do
      with_layout_dir do |root|
        path = touch(root, "api", "api", "x.ts")
        Noir::ServerlessLayout.routing_remainder(path, "/api/api/x.ts", "api").should eq({root, ["api", "x.ts"]})
      end
    end

    it "returns nil when the routing dir name is the file itself or is absent" do
      with_layout_dir do |root|
        Noir::ServerlessLayout.routing_remainder(File.join(root, "api"), "/api", "api").should be_nil
        Noir::ServerlessLayout.routing_remainder(File.join(root, "x", "api"), "/x/api", "api").should be_nil
        Noir::ServerlessLayout.routing_remainder(File.join(root, "src", "x.ts"), "/src/x.ts", "api").should be_nil
      end
    end
  end

  describe ".project_root?" do
    it "accepts every project marker" do
      Noir::ServerlessLayout::PROJECT_MARKERS.each do |marker|
        with_layout_dir do |root|
          touch(root, marker)
          Noir::ServerlessLayout.project_root?(root).should be_true
        end
      end
    end

    it "rejects a directory without a marker" do
      with_layout_dir do |root|
        touch(root, "index.ts")
        Noir::ServerlessLayout.project_root?(root).should be_false
      end
    end
  end

  describe ".ancestor" do
    it "applies File.dirname the given number of times" do
      Noir::ServerlessLayout.ancestor("/a/b/c/d.ts", 0).should eq("/a/b/c/d.ts")
      Noir::ServerlessLayout.ancestor("/a/b/c/d.ts", 1).should eq("/a/b/c")
      Noir::ServerlessLayout.ancestor("/a/b/c/d.ts", 3).should eq("/a")
    end
  end

  describe ".vercel_project?" do
    it "accepts a root with vercel.json or now.json" do
      Noir::ServerlessLayout::VERCEL_CONFIGS.each do |config|
        with_layout_dir do |root|
          touch(root, config, content: "{}")
          Noir::ServerlessLayout.vercel_project?(root).should be_true
        end
      end
    end

    it "accepts a package.json that depends on the Vercel runtime types" do
      {"@vercel/node", "@vercel/functions"}.each do |package|
        with_layout_dir do |root|
          touch(root, "package.json", content: %({"devDependencies": {"#{package}": "^5.0.0"}}))
          Noir::ServerlessLayout.vercel_project?(root).should be_true
        end
      end
    end

    it "rejects a package.json without them, and a root without either file" do
      with_layout_dir do |root|
        Noir::ServerlessLayout.vercel_project?(root).should be_false
        touch(root, "package.json", content: %({"dependencies": {"express": "^4.0.0", "@vercel/analytics": "^1.0.0"}}))
        Noir::ServerlessLayout.vercel_project?(root).should be_false
      end
    end
  end

  describe "VERCEL_IMPORT" do
    it "matches an import, a require and a dynamic import of the runtime types" do
      [
        %(import type { VercelRequest } from "@vercel/node";),
        %(import { waitUntil } from '@vercel/functions'),
        %(const { geolocation } = require("@vercel/functions")),
        %(const mod = await import('@vercel/node')),
      ].each do |line|
        line.matches?(Noir::ServerlessLayout::VERCEL_IMPORT).should be_true
      end
    end

    it "does not match another Vercel package or a bare mention" do
      [
        %(import { track } from "@vercel/analytics"),
        %(import { kv } from "@vercel/node-kv"),
        %(// uses "@vercel/node"),
      ].each do |line|
        line.matches?(Noir::ServerlessLayout::VERCEL_IMPORT).should be_false
      end
    end
  end

  describe ".netlify_default_remainder" do
    it "finds netlify/functions and netlify/edge-functions" do
      Noir::ServerlessLayout.netlify_default_remainder("/netlify/functions/hello.mts").should eq({"functions", ["hello.mts"]})
      Noir::ServerlessLayout.netlify_default_remainder("/netlify/edge-functions/geo/index.ts").should eq({"edge-functions", ["geo", "index.ts"]})
    end

    it "finds them below a site base directory" do
      Noir::ServerlessLayout.netlify_default_remainder("/sites/docs/netlify/functions/hello.mts").should eq({"functions", ["hello.mts"]})
    end

    it "returns nil for another netlify subdirectory or a bare functions directory" do
      Noir::ServerlessLayout.netlify_default_remainder("/netlify/plugins/hello.mts").should be_nil
      Noir::ServerlessLayout.netlify_default_remainder("/functions/hello.mts").should be_nil
    end

    it "returns nil when nothing sits below the functions directory" do
      Noir::ServerlessLayout.netlify_default_remainder("/netlify/functions").should be_nil
      Noir::ServerlessLayout.netlify_default_remainder("").should be_nil
    end
  end

  describe ".netlify_function_name" do
    it "names a top-level file after its stem" do
      Noir::ServerlessLayout.netlify_function_name(["hello.mts"]).should eq("hello")
    end

    it "names a directory function after the directory" do
      Noir::ServerlessLayout.netlify_function_name(["hello", "hello.mts"]).should eq("hello")
      Noir::ServerlessLayout.netlify_function_name(["hello", "index.mts"]).should eq("hello")
    end

    it "returns nil for a sibling module in a function's directory" do
      Noir::ServerlessLayout.netlify_function_name(["hello", "util.mts"]).should be_nil
    end

    it "returns nil for anything deeper, and for no segments" do
      Noir::ServerlessLayout.netlify_function_name(["hello", "lib", "index.mts"]).should be_nil
      Noir::ServerlessLayout.netlify_function_name([] of String).should be_nil
    end
  end

  describe ".stem" do
    it "drops only the last extension" do
      Noir::ServerlessLayout.stem("hello.mts").should eq("hello")
      Noir::ServerlessLayout.stem("[id].ts").should eq("[id]")
      Noir::ServerlessLayout.stem("hello.test.ts").should eq("hello.test")
      Noir::ServerlessLayout.stem("hello").should eq("hello")
    end
  end

  describe ".non_handler_file?" do
    it "accepts colocated tests in every JS and TS extension" do
      %w[x.test.ts x.spec.js x.test.mjs x.spec.cts x.test.tsx x.spec.jsx].each do |path|
        Noir::ServerlessLayout.non_handler_file?(path).should be_true
      end
    end

    it "accepts type declarations" do
      %w[x.d.ts x.d.mts x.d.cts].each do |path|
        Noir::ServerlessLayout.non_handler_file?(path).should be_true
      end
    end

    it "rejects a handler, including one named test or spec" do
      %w[x.ts api/users.js test.ts spec.js contest.ts x.tests.ts x.test.py].each do |path|
        Noir::ServerlessLayout.non_handler_file?(path).should be_false
      end
    end
  end

  describe ".private_segment?" do
    it "accepts a hidden or underscore-prefixed segment at any depth" do
      Noir::ServerlessLayout.private_segment?([".hidden", "x.ts"]).should be_true
      Noir::ServerlessLayout.private_segment?(["users", "_utils.ts"]).should be_true
      Noir::ServerlessLayout.private_segment?(["_lib", "db", "x.ts"]).should be_true
    end

    it "rejects public segments, an underscore elsewhere in a name, and no segments" do
      Noir::ServerlessLayout.private_segment?(["users", "[id].ts"]).should be_false
      Noir::ServerlessLayout.private_segment?(["user_list.ts"]).should be_false
      Noir::ServerlessLayout.private_segment?([] of String).should be_false
    end
  end
end
