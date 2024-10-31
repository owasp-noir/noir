require "../../../../src/detector/detectors/*"

describe "Detect Python FastAPI" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Python::FastAPI.new options

  it "settings.py" do
    instance.detect("settings.py", "from fastapi").should eq(true)
  end
end
