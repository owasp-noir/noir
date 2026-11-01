require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/n8n"

describe "Detect TypeScript n8n decorators" do
  options = create_test_options
  instance = Detector::Typescript::N8n.new options

  it "import_n8n_decorators" do
    instance.detect("auth.controller.ts", "import { Get, RestController } from '@n8n/decorators';").should be_true
  end

  it "package_json_dependency" do
    instance.detect("package.json", "{\"dependencies\": {\"@n8n/decorators\": \"workspace:*\"}}").should be_true
  end

  it "should_not_detect_other_n8n_packages" do
    instance.detect("node.ts", "import { NodeOperationError } from 'n8n-workflow';").should be_false
    instance.detect("di.ts", "import { Service } from '@n8n/di';").should be_false
    instance.detect("package.json", "{\"dependencies\": {\"@n8n/di\": \"workspace:*\"}}").should be_false
  end

  it "should_not_detect_nestjs" do
    instance.detect("users.controller.ts", "import { Controller } from '@nestjs/common';\n@Controller('users')").should be_false
  end
end
