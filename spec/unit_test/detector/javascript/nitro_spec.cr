require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Nitro" do
  options = create_test_options
  instance = Detector::Javascript::Nitro.new options

  it "nitro_config_ts" do
    instance.detect("nitro.config.ts", "export default defineNitroConfig({})").should be_true
  end

  it "nitro_config_js" do
    instance.detect("nitro.config.js", "export default defineNitroConfig({})").should be_true
  end

  it "require_single_quot" do
    instance.detect("index.js", "require('nitropack')").should be_true
  end

  it "require_double_quot" do
    instance.detect("index.js", "require(\"nitropack\")").should be_true
  end

  it "import_single_quot" do
    instance.detect("index.js", "import { defineNitroConfig } from 'nitropack'").should be_true
  end

  it "import_double_quot" do
    instance.detect("index.js", "import { defineNitroConfig } from \"nitropack\"").should be_true
  end

  it "define_nitro_config" do
    instance.detect("nitro.config.ts", "defineNitroConfig({ compatibilityDate: '2025-01-01' })").should be_true
  end

  it "ts_file" do
    instance.detect("nitro.config.ts", "import { defineNitroConfig } from 'nitropack'").should be_true
  end

  it "mjs_file" do
    instance.detect("index.mjs", "import { defineNitroConfig } from 'nitropack'").should be_true
  end

  it "cjs_file" do
    instance.detect("index.cjs", "require('nitropack')").should be_true
  end

  it "not_detect_other_framework" do
    instance.detect("index.js", "require('express')").should be_false
  end

  it "not_detect_non_js_file" do
    instance.detect("index.py", "import { defineNitroConfig } from 'nitropack'").should be_false
  end
end
