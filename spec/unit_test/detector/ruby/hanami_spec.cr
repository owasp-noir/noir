require "../../../../src/detector/detectors/*"

describe "Detect Ruby Hanami" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Ruby::Hanami.new options

  it "gemfile/single_quot" do
    instance.detect("Gemfile", "gem 'hanami'").should eq(true)
  end
  it "gemfile/double_quot" do
    instance.detect("Gemfile", "gem \"hanami\"").should eq(true)
  end
end
