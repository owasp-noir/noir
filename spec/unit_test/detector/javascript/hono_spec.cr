require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Hono" do
  options = create_test_options
  instance = Detector::Javascript::Hono.new options

  it "require_single_quot" do
    instance.detect("index.js", "require('hono')").should be_true
  end

  it "require_double_quot" do
    instance.detect("index.js", "require(\"hono\")").should be_true
  end

  it "import_single_quot" do
    instance.detect("index.js", "import { Hono } from 'hono'").should be_true
  end

  it "import_double_quot" do
    instance.detect("index.js", "import { Hono } from \"hono\"").should be_true
  end

  it "const_require_single_quot" do
    instance.detect("index.js", "const { Hono } = require('hono')").should be_true
  end

  it "const_require_double_quot" do
    instance.detect("index.js", "const { Hono } = require(\"hono\")").should be_true
  end

  it "new_hono_instance" do
    instance.detect("index.ts", "const app = new Hono()").should be_true
  end

  it "new_hono_instance_with_options" do
    instance.detect("index.ts", "const app = new Hono({ strict: false })").should be_true
  end

  it "ts_file" do
    instance.detect("index.ts", "import { Hono } from 'hono'").should be_true
  end

  it "tsx_file" do
    instance.detect("index.tsx", "import { Hono } from 'hono'").should be_true
  end

  it "jsx_file" do
    instance.detect("index.jsx", "import { Hono } from 'hono'").should be_true
  end

  it "mjs_file" do
    instance.detect("index.mjs", "import { Hono } from 'hono'").should be_true
  end

  it "cjs_file" do
    instance.detect("index.cjs", "const { Hono } = require('hono')").should be_true
  end

  it "not_detect_other_framework" do
    instance.detect("index.js", "require('express')").should be_false
  end

  it "not_detect_non_js_file" do
    instance.detect("index.py", "import { Hono } from 'hono'").should be_false
  end
end
