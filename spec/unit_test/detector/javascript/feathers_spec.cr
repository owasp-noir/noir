require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/*"

describe "Detect JS Feathers" do
  options = create_test_options
  instance = Detector::Javascript::Feathers.new options

  it "package_json_feathers_core" do
    instance.detect("package.json", %({"dependencies": {"@feathersjs/feathers": "^5.0.0"}})).should be_true
  end

  it "package_json_feathers_express" do
    instance.detect("package.json", %({"dependencies": {"@feathersjs/express": "^5.0.0"}})).should be_true
  end

  it "package_json_unrelated" do
    instance.detect("package.json", %({"dependencies": {"express": "^4.18.0"}})).should be_false
  end

  it "require_single_quot" do
    instance.detect("app.js", "const { feathers } = require('@feathersjs/feathers')").should be_true
  end

  it "require_double_quot" do
    instance.detect("app.js", "const { feathers } = require(\"@feathersjs/feathers\")").should be_true
  end

  it "import_from" do
    instance.detect("app.ts", "import { feathers } from '@feathersjs/feathers'").should be_true
  end

  it "express_submodule_require" do
    instance.detect("app.js", "const express = require('@feathersjs/express')").should be_true
  end

  it "express_rest_submodule" do
    instance.detect("app.js", "const { rest } = require('@feathersjs/express/rest')").should be_true
  end

  it "koa_transport" do
    instance.detect("app.js", "const { koa } = require('@feathersjs/koa')").should be_true
  end

  it "feathers_factory_call" do
    instance.detect("app.js", "const app = feathers()").should be_true
  end

  it "app_service_call" do
    instance.detect("services.js", "app.service('messages').hooks({})").should be_true
  end

  it "plain_express_is_not_feathers" do
    instance.detect("app.js", "const express = require('express')\nconst app = express()").should be_false
  end

  it "unrelated_js_file" do
    instance.detect("index.js", "console.log('hello world')").should be_false
  end

  it "wrong_extension" do
    instance.detect("readme.md", "require('@feathersjs/feathers')").should be_false
  end
end
