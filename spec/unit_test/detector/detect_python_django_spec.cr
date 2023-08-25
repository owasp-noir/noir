require "../../../src/detector/detectors/*"

describe "Detect Python Django" do
  options = default_options()
  instance = DetectorPythonDjango.new options

  it "settings.py" do
    instance.detect("settings.py", "from django.apps import AppConfig").should eq(true)
  end
end
