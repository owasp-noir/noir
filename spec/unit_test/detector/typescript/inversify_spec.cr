require "../../../spec_helper"
require "../../../../src/detector/detectors/typescript/inversify"

describe "Detect TypeScript inversify-express-utils" do
  options = create_test_options
  instance = Detector::Typescript::Inversify.new options

  it "import_inversify_express_utils" do
    instance.detect("UserController.ts", "import { controller, httpGet } from \"inversify-express-utils\";").should be_true
  end

  it "package_json_dependency" do
    instance.detect("package.json", "{\"dependencies\": {\"inversify-express-utils\": \"^6.4.6\"}}").should be_true
  end

  it "should_not_detect_plain_inversify" do
    instance.detect("container.ts", "import { Container } from 'inversify';").should be_false
    instance.detect("package.json", "{\"dependencies\": {\"inversify\": \"^6.0.0\"}}").should be_false
  end
end
