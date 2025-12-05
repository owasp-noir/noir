require "../../../spec_helper"
require "../../../../src/detector/detectors/javascript/nestjs"

describe "Detect JS NestJS" do
  options = create_test_options
  instance = Detector::Javascript::Nestjs.new options

  it "require_nestjs_core_single_quot" do
    instance.detect("app.ts", "require('@nestjs/core')").should eq(true)
  end

  it "require_nestjs_core_double_quot" do
    instance.detect("app.ts", "require(\"@nestjs/core\")").should eq(true)
  end

  it "require_nestjs_common_single_quot" do
    instance.detect("controller.ts", "require('@nestjs/common')").should eq(true)
  end

  it "require_nestjs_common_double_quot" do
    instance.detect("controller.ts", "require(\"@nestjs/common\")").should eq(true)
  end

  it "import_nestjs_core_single_quot" do
    instance.detect("main.ts", "import { NestFactory } from '@nestjs/core'").should eq(true)
  end

  it "import_nestjs_core_double_quot" do
    instance.detect("main.ts", "import { NestFactory } from \"@nestjs/core\"").should eq(true)
  end

  it "import_nestjs_common_single_quot" do
    instance.detect("controller.ts", "import { Controller, Get } from '@nestjs/common'").should eq(true)
  end

  it "import_nestjs_common_double_quot" do
    instance.detect("controller.ts", "import { Controller, Get } from \"@nestjs/common\"").should eq(true)
  end

  it "controller_decorator" do
    instance.detect("user.controller.ts", "@Controller('users')").should eq(true)
  end

  it "module_decorator" do
    instance.detect("app.module.ts", "@Module({ imports: [] })").should eq(true)
  end

  it "nest_factory_create" do
    instance.detect("main.ts", "const app = await NestFactory.create(AppModule);").should eq(true)
  end

  it "javascript_file" do
    instance.detect("app.js", "import { NestFactory } from '@nestjs/core'").should eq(true)
  end

  it "jsx_file" do
    instance.detect("component.jsx", "@Controller('api')").should eq(true)
  end

  it "tsx_file" do
    instance.detect("component.tsx", "@Controller('api')").should eq(true)
  end

  it "should_not_detect_non_nestjs" do
    instance.detect("app.ts", "import express from 'express'").should eq(false)
  end

  it "should_not_detect_wrong_file_extension" do
    instance.detect("app.py", "@Controller('users')").should eq(false)
  end
end
