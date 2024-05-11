require "../../../src/detector/detectors/*"

describe "Detect Ruby Hanami" do
  options = default_options()
  instance = DetectorRubyHanami.new options

  it "gemfile/single_quot" do
    instance.detect("Gemfile", "gem 'hanami'").should eq(true)
  end
  it "gemfile/double_quot" do
    instance.detect("Gemfile", "gem \"hanami\"").should eq(true)
  end
end
