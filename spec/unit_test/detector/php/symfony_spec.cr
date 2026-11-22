require "../../../spec_helper"
require "../../../../src/detector/detector"

# Direct detection also recognizes this file outside the scanner dispatch gate.
describe "php_symfony direct detection" do
  instance = build_detector_list(create_test_options).find! { |detector| detector.name == "php_symfony" }

  it "detects config/services.yaml with App\\" do
    content = <<-YAML
      services:
        App\\:
          resource: '../src/'
      YAML
    instance.detect("config/services.yaml", content).should be_true
  end
end
