require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Django" do
  options = create_test_options
  instance = Detector::Python::Django.new options

  it "settings.py" do
    instance.detect("settings.py", "from django.apps import AppConfig").should eq(true)
  end
end
