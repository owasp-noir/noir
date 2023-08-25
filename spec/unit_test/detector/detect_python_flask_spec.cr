require "../../../src/detector/detectors/*"

describe "Detect Python Flask" do
  options = default_options()
  instance = DetectorPythonFlask.new options

  it "detect_flask - app.py" do
    instance.detect("app.py", "from flask import Flask").should eq(true)
  end
end
