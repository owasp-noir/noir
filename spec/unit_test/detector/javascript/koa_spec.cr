require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Koa" do
  options = create_test_options
  instance = Detector::Javascript::Koa.new options

  it "require_single_quot" do
    instance.detect("index.js", "require('koa')").should eq(true)
  end

  it "require_double_quot" do
    instance.detect("index.js", "require(\"koa\")").should eq(true)
  end

  it "import_single_quot" do
    instance.detect("index.js", "import Koa from 'koa'").should eq(true)
  end

  it "import_double_quot" do
    instance.detect("index.js", "import Koa from \"koa\"").should eq(true)
  end

  it "const_require_single_quot" do
    instance.detect("index.js", "const Koa = require('koa')").should eq(true)
  end

  it "const_require_double_quot" do
    instance.detect("index.js", "const Koa = require(\"koa\")").should eq(true)
  end

  it "let_require_single_quot" do
    instance.detect("index.js", "let Koa = require('koa')").should eq(true)
  end

  it "let_require_double_quot" do
    instance.detect("index.js", "let Koa = require(\"koa\")").should eq(true)
  end

  it "var_require_single_quot" do
    instance.detect("index.js", "var Koa = require('koa')").should eq(true)
  end

  it "var_require_double_quot" do
    instance.detect("index.js", "var Koa = require(\"koa\")").should eq(true)
  end

  it "new_koa_instance" do
    instance.detect("index.js", "const app = new Koa()").should eq(true)
  end

  it "koa_router_single_quot" do
    instance.detect("index.js", "const Router = require('koa-router')").should eq(true)
  end

  it "koa_router_double_quot" do
    instance.detect("index.js", "const Router = require(\"koa-router\")").should eq(true)
  end

  it "import_koa_router_single_quot" do
    instance.detect("index.js", "import Router from 'koa-router'").should eq(true)
  end

  it "import_koa_router_double_quot" do
    instance.detect("index.js", "import Router from \"koa-router\"").should eq(true)
  end

  it "koa_common_middleware_single_quot" do
    instance.detect("index.js", "const bodyParser = require('koa-bodyparser')").should eq(true)
  end

  it "koa_common_middleware_double_quot" do
    instance.detect("index.js", "const bodyParser = require(\"koa-bodyparser\")").should eq(true)
  end
end
