require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/tsed"

describe "Detect TypeScript Ts.ED" do
  options = create_test_options
  instance = Detector::Typescript::Tsed.new options

  it "import_tsed_di" do
    instance.detect("CalendarsController.ts", "import { Controller } from \"@tsed/di\";").should be_true
  end

  it "import_tsed_schema" do
    instance.detect("CalendarsController.ts", "import { Get } from '@tsed/schema';").should be_true
  end

  it "import_tsed_common_legacy" do
    instance.detect("Server.ts", "import { Controller, Get } from \"@tsed/common\";").should be_true
  end

  it "package_json_dependency" do
    instance.detect("package.json", "{\"dependencies\": {\"@tsed/platform-express\": \"^8.0.0\"}}").should be_true
  end

  it "should_not_detect_non_routing_tsed_package" do
    instance.detect("logger.ts", "import { Logger } from '@tsed/logger';").should be_false
    instance.detect("package.json", "{\"dependencies\": {\"@tsed/logger\": \"^6.0.0\"}}").should be_false
  end

  it "should_not_detect_nestjs" do
    instance.detect("users.controller.ts", "import { Controller } from '@nestjs/common';\n@Controller('users')").should be_false
  end
end
