require "../../../src/models/detector.cr"
require "../../../src/options.cr"

describe "Initialize" do
  options = default_options
  options[:base] = "noir"
  object = Detector.new(options)

  it "getter - name" do
    object.name.should eq("")
  end
end
