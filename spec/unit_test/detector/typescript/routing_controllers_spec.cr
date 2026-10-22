require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/routing_controllers"

describe "Detect TypeScript routing-controllers" do
  options = create_test_options
  instance = Detector::Typescript::RoutingControllers.new options

  it "import_routing_controllers" do
    instance.detect("UserController.ts", "import { JsonController, Get } from 'routing-controllers';").should be_true
  end

  it "multiline_import" do
    instance.detect("app.ts", "import {\n  createExpressServer,\n} from \"routing-controllers\";").should be_true
  end

  it "package_json_dependency" do
    instance.detect("package.json", "{\"dependencies\": {\"routing-controllers\": \"^0.10.4\"}}").should be_true
  end

  it "should_not_detect_nestjs" do
    instance.detect("users.controller.ts", "import { Controller, Get } from '@nestjs/common';\n@Controller('users')").should be_false
  end

  it "should_not_detect_javascript_file" do
    instance.detect("app.js", "import { Get } from 'routing-controllers';").should be_false
  end
end
