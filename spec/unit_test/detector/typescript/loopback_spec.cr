require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/loopback"

describe "Detect TypeScript LoopBack" do
  options = create_test_options
  instance = Detector::Typescript::Loopback.new options

  it "import_loopback_rest_single_quot" do
    instance.detect("user.controller.ts", "import {get, post} from '@loopback/rest'").should be_true
  end

  it "import_loopback_rest_double_quot" do
    instance.detect("user.controller.ts", "import {get, post} from \"@loopback/rest\"").should be_true
  end

  it "import_loopback_core_single_quot" do
    instance.detect("application.ts", "import {RestApplication} from '@loopback/rest'\nimport {BootMixin} from '@loopback/core'").should be_true
  end

  it "import_loopback_rest_multiline_block" do
    instance.detect("user.controller.ts", "import {\n  get,\n  post,\n  param,\n} from '@loopback/rest';").should be_true
  end

  it "require_loopback_rest_single_quot" do
    instance.detect("app.ts", "require('@loopback/rest')").should be_true
  end

  it "require_loopback_rest_double_quot" do
    instance.detect("app.ts", "require(\"@loopback/rest\")").should be_true
  end

  it "require_loopback_core_single_quot" do
    instance.detect("app.ts", "require('@loopback/core')").should be_true
  end

  it "require_loopback_core_double_quot" do
    instance.detect("app.ts", "require(\"@loopback/core\")").should be_true
  end

  it "package_json_loopback_core_dependency" do
    instance.detect("package.json", %({"dependencies": {"@loopback/core": "4.0.0"}})).should be_true
  end

  it "package_json_loopback_rest_dependency" do
    instance.detect("package.json", %({"dependencies": {"@loopback/rest": "12.0.0"}})).should be_true
  end

  it "package_json_without_loopback" do
    instance.detect("package.json", %({"dependencies": {"express": "4.18.0"}})).should be_false
  end

  it "tsx_file" do
    instance.detect("component.tsx", "import {get} from '@loopback/rest'").should be_true
  end

  it "should_not_detect_non_loopback" do
    instance.detect("app.ts", "import express from 'express'").should be_false
  end

  it "should_not_detect_lookalike_lowercase_decorators_without_import" do
    # NestJS-adjacent / other decorator-based TS libraries can define their
    # own lowercase `@get`/`@post` decorators. Without a genuine
    # `@loopback/*` import this must not be misclassified as LoopBack.
    instance.detect("other.controller.ts", "@get('/x')\nclass X {}").should be_false
  end

  it "should_not_detect_javascript_file" do
    instance.detect("app.js", "import {get} from '@loopback/rest'").should be_false
  end

  it "should_not_detect_wrong_file_extension" do
    instance.detect("app.py", "import {get} from '@loopback/rest'").should be_false
  end
end
