require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/nestjs"

describe "Detect JS NestJS" do
  options = create_test_options
  instance = Detector::Javascript::Nestjs.new options

  it "require_nestjs_core_single_quot" do
    instance.detect("app.js", "require('@nestjs/core')").should be_true
  end

  it "require_nestjs_core_double_quot" do
    instance.detect("app.js", "require(\"@nestjs/core\")").should be_true
  end

  it "require_nestjs_common_single_quot" do
    instance.detect("controller.js", "require('@nestjs/common')").should be_true
  end

  it "require_nestjs_common_double_quot" do
    instance.detect("controller.js", "require(\"@nestjs/common\")").should be_true
  end

  it "import_nestjs_core_single_quot" do
    instance.detect("main.js", "import { NestFactory } from '@nestjs/core'").should be_true
  end

  it "import_nestjs_core_double_quot" do
    instance.detect("main.js", "import { NestFactory } from \"@nestjs/core\"").should be_true
  end

  it "import_nestjs_common_single_quot" do
    instance.detect("controller.js", "import { Controller, Get } from '@nestjs/common'").should be_true
  end

  it "import_nestjs_common_double_quot" do
    instance.detect("controller.js", "import { Controller, Get } from \"@nestjs/common\"").should be_true
  end

  it "controller_decorator" do
    instance.detect("user.controller.js", "@Controller('users')").should be_true
  end

  it "module_decorator" do
    instance.detect("app.module.js", "@Module({ imports: [] })").should be_true
  end

  it "nest_factory_create" do
    instance.detect("main.js", "const app = await NestFactory.create(AppModule);").should be_true
  end

  it "javascript_file" do
    instance.detect("app.js", "import { NestFactory } from '@nestjs/core'").should be_true
  end

  it "jsx_file" do
    instance.detect("component.jsx", "@Controller('api')").should be_true
  end

  it "should_not_detect_typescript_file" do
    instance.detect("component.ts", "@Controller('api')").should be_false
  end

  it "should_not_detect_tsx_file" do
    instance.detect("component.tsx", "@Controller('api')").should be_false
  end

  it "should_not_detect_non_nestjs" do
    instance.detect("app.js", "import express from 'express'").should be_false
  end

  it "should_not_detect_wrong_file_extension" do
    instance.detect("app.py", "@Controller('users')").should be_false
  end
end
