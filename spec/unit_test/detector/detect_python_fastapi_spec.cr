require "../../../src/detector/detectors/*"

describe "Detect Python FastAPI" do
  options = default_options()
  instance = DetectorPythonFastAPI.new options

  it "settings.py" do
    instance.detect("settings.py", "from fastapi").should eq(true)
  end
end
