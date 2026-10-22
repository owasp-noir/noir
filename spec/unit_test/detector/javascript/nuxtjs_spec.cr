require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/nuxtjs"

describe "Detect JS Nuxtjs" do
  options = create_test_options
  instance = Detector::Javascript::Nuxtjs.new options

  it "detects nuxt config files" do
    instance.applicable?("nuxt.config.js").should be_true
    instance.detect("nuxt.config.js", "export default defineNuxtConfig({})").should be_true

    instance.applicable?("nuxt.config.ts").should be_true
    instance.detect("nuxt.config.ts", "export default defineNuxtConfig({})").should be_true

    instance.applicable?("nuxt.config.mjs").should be_true
    instance.detect("nuxt.config.mjs", "export default defineNuxtConfig({})").should be_true
  end

  it "detects nuxt imports in source files" do
    instance.applicable?("app.ts").should be_true
    instance.detect("app.ts", "import { defineNuxtConfig } from 'nuxt';").should be_true
    instance.detect("app.ts", "import { useAppConfig } from '#app';").should be_true
    instance.detect("app.ts", "import { defineNuxtModule } from '@nuxt/kit';").should be_true

    instance.applicable?("app.mjs").should be_true
    instance.detect("app.mjs", "import { defineNuxtConfig } from 'nuxt';").should be_true

    instance.applicable?("app.js").should be_true
    instance.detect("app.js", "const nuxt = require('nuxt');").should be_true
  end

  it "detects nuxt as a package.json dependency" do
    instance.applicable?("package.json").should be_true
    instance.detect("package.json", %({"devDependencies":{"nuxt":"^3.11.0"}})).should be_true
    instance.detect("package.json", %({"dependencies":{"nitropack":"2.9.0"}})).should be_false
    instance.detect("package.json", %({"keywords":["nuxt"],"dependencies":{"nitropack":"2.9.0"}})).should be_false
  end

  it "does not claim plain Nitro/h3 server routes" do
    handler = "export default defineEventHandler((event) => { return []; });"
    instance.detect("/server/api/users.ts", handler).should be_false
    instance.detect("/server/routes/test.mjs", handler).should be_false
    instance.detect("nitro.config.ts", "export default defineNitroConfig({})").should be_false
  end

  it "does not detect unrelated files" do
    instance.detect("app.js", "console.log('hello');").should be_false
    instance.applicable?("app.py").should be_false
  end
end
