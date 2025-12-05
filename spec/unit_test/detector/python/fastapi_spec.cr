require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python FastAPI" do
  options = create_test_options
  instance = Detector::Python::FastAPI.new options

  it "settings.py" do
    instance.detect("settings.py", "from fastapi").should eq(true)
  end
end
