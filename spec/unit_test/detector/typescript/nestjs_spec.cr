require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/nestjs"

describe "Detect TypeScript NestJS" do
  options = create_test_options
  instance = Detector::Typescript::Nestjs.new options

  it "require_nestjs_core_single_quot" do
    instance.detect("app.ts", "require('@nestjs/core')").should be_true
  end

  it "require_nestjs_core_double_quot" do
    instance.detect("app.ts", "require(\"@nestjs/core\")").should be_true
  end

  it "require_nestjs_common_single_quot" do
    instance.detect("controller.ts", "require('@nestjs/common')").should be_true
  end

  it "require_nestjs_common_double_quot" do
    instance.detect("controller.ts", "require(\"@nestjs/common\")").should be_true
  end

  it "import_nestjs_core_single_quot" do
    instance.detect("main.ts", "import { NestFactory } from '@nestjs/core'").should be_true
  end

  it "import_nestjs_core_double_quot" do
    instance.detect("main.ts", "import { NestFactory } from \"@nestjs/core\"").should be_true
  end

  it "import_nestjs_common_single_quot" do
    instance.detect("controller.ts", "import { Controller, Get } from '@nestjs/common'").should be_true
  end

  it "import_nestjs_common_double_quot" do
    instance.detect("controller.ts", "import { Controller, Get } from \"@nestjs/common\"").should be_true
  end

  it "controller_decorator" do
    instance.detect("user.controller.ts", "@Controller('users')").should be_true
  end

  it "module_decorator" do
    instance.detect("app.module.ts", "@Module({ imports: [] })").should be_true
  end

  it "nest_factory_create" do
    instance.detect("main.ts", "const app = await NestFactory.create(AppModule);").should be_true
  end

  it "tsx_file" do
    instance.detect("component.tsx", "@Controller('api')").should be_true
  end

  it "should_not_detect_non_nestjs" do
    instance.detect("app.ts", "import express from 'express'").should be_false
  end

  it "should_not_detect_javascript_file" do
    instance.detect("app.js", "import { NestFactory } from '@nestjs/core'").should be_false
  end

  it "should_not_detect_wrong_file_extension" do
    instance.detect("app.py", "@Controller('users')").should be_false
  end
end
