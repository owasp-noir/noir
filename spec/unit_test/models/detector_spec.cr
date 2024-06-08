require "../../../src/models/detector.cr"
require "../../../src/config_initializer.cr"

describe "Initialize" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = "noir"
  object = Detector.new(options)

  it "getter - name" do
    object.name.should eq("")
  end
end
