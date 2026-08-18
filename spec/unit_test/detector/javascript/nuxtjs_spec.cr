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

  it "detects server routes with defineEventHandler including .mts" do
    instance.applicable?("/server/api/users.mts").should be_true
    instance.detect("/server/api/users.mts", "export default defineEventHandler((event) => { return []; });").should be_true

    instance.applicable?("/server/api/users.ts").should be_true
    instance.detect("/server/api/users.ts", "export default defineEventHandler((event) => { return []; });").should be_true

    instance.applicable?("/server/routes/test.mjs").should be_true
    instance.detect("/server/routes/test.mjs", "export default defineEventHandler((event) => { return []; });").should be_true

    instance.applicable?("/server/routes/test.js").should be_true
    instance.detect("/server/routes/test.js", "export default defineEventHandler((event) => { return []; });").should be_true
  end

  it "does not detect server route directory without defineEventHandler" do
    instance.detect("/server/api/users.mts", "export const router = express.Router();").should be_false
  end

  it "does not detect unrelated files" do
    instance.detect("app.js", "console.log('hello');").should be_false
    instance.applicable?("app.py").should be_false
  end
end
