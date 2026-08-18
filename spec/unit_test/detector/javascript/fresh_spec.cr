require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/fresh"

describe "Detect JS Fresh" do
  options = create_test_options
  instance = Detector::Javascript::Fresh.new options

  it "detects deno.json with $fresh/ marker" do
    instance.applicable?("deno.json").should be_true
    content = %({"imports": {"$fresh/": "https://deno.land/x/fresh@1.6.8/"}})
    instance.detect("deno.json", content).should be_true
  end

  it "detects deno.jsonc with $fresh/ marker" do
    instance.applicable?("deno.jsonc").should be_true
    content = %({"imports": {"$fresh/": "https://deno.land/x/fresh@1.6.8/"}})
    instance.detect("deno.jsonc", content).should be_true
  end

  it "detects fresh.config files" do
    instance.applicable?("fresh.config.ts").should be_true
    instance.detect("fresh.config.ts", "import { defineConfig } from '$fresh/server.ts';").should be_true

    instance.applicable?("fresh.config.js").should be_true
    instance.detect("fresh.config.js", "export default {};").should be_true
  end

  it "detects main.ts with $fresh/ marker" do
    instance.applicable?("main.ts").should be_true
    instance.detect("main.ts", %(import { start } from "$fresh/server.ts";)).should be_true
  end

  it "detects source files with $fresh/ marker" do
    instance.applicable?("routes/index.tsx").should be_true
    instance.detect("routes/index.tsx", %(import { Handlers } from "$fresh/server.ts";)).should be_true

    instance.applicable?("routes/api/users.ts").should be_true
    instance.detect("routes/api/users.ts", %(import { FreshContext } from "$fresh/server.ts";)).should be_true

    instance.applicable?("routes/index.js").should be_true
    instance.detect("routes/index.js", %(import { Handlers } from "$fresh/server.ts";)).should be_true

    instance.applicable?("routes/index.jsx").should be_true
    instance.detect("routes/index.jsx", %(import { Handlers } from "$fresh/server.ts";)).should be_true
  end

  it "does not detect deno.json without fresh marker" do
    instance.detect("deno.json", %({"tasks": {"start": "deno run main.ts"}})).should be_false
  end

  it "does not detect main.ts without fresh marker" do
    instance.detect("main.ts", "console.log('hello');").should be_false
  end

  it "does not detect unrelated files" do
    instance.detect("app.js", "console.log('hello')").should be_false
    instance.applicable?("main.py").should be_false
  end
end
