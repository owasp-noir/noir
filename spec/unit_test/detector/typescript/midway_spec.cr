require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/midway"

describe "Detect TypeScript Midway" do
  options = create_test_options
  instance = Detector::Typescript::Midway.new options

  it "import_midway_core" do
    instance.detect("user.controller.ts", "import { Controller, Get } from '@midwayjs/core';").should be_true
  end

  it "import_midway_decorator_v2" do
    instance.detect("home.controller.ts", "import { Controller, Get, Provide } from \"@midwayjs/decorator\";").should be_true
  end

  it "import_midway_multiline_block" do
    instance.detect("user.controller.ts", "import {\n  Controller,\n  Get,\n} from '@midwayjs/core';").should be_true
  end

  it "require_midway_core" do
    instance.detect("app.ts", "const { Controller } = require('@midwayjs/core');").should be_true
  end

  it "package_json_dependency" do
    instance.detect("package.json", "{\"dependencies\": {\"@midwayjs/core\": \"^3.12.0\"}}").should be_true
    instance.detect("package.json", "{\"dependencies\": {\"@midwayjs/decorator\": \"^2.3.0\"}}").should be_true
  end

  it "should_not_detect_nestjs" do
    instance.detect("user.controller.ts", "import { Controller, Get } from '@nestjs/common';\n@Controller('api')").should be_false
    instance.detect("package.json", "{\"dependencies\": {\"@nestjs/core\": \"^10.0.0\"}}").should be_false
  end

  it "should_not_detect_javascript_file" do
    instance.detect("app.js", "import { Controller } from '@midwayjs/core';").should be_false
  end
end
