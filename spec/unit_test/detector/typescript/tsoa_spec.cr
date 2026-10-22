require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/tsoa"

describe "Detect TypeScript tsoa" do
  options = create_test_options
  instance = Detector::Typescript::Tsoa.new options

  it "import_tsoa" do
    instance.detect("usersController.ts", "import { Controller, Get, Route } from \"tsoa\";").should be_true
  end

  it "import_tsoa_runtime" do
    instance.detect("routes.ts", "import { fetchMiddlewares } from '@tsoa/runtime';").should be_true
  end

  it "package_json_dependency" do
    instance.detect("package.json", "{\"dependencies\": {\"tsoa\": \"^6.4.0\"}}").should be_true
  end

  it "should_not_detect_other_packages" do
    instance.detect("app.ts", "import { Controller } from '@nestjs/common';").should be_false
    instance.detect("app.ts", "import { tsoaHelper } from './tsoa-helper';").should be_false
    instance.detect("package.json", "{\"dependencies\": {\"tsoa-zod\": \"^1.0.0\"}}").should be_false
  end
end
