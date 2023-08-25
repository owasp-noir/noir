require "../../../src/detector/detectors/*"

describe "Detect Ruby Sinatra" do
  options = default_options()
  instance = DetectorRubySinatra.new options

  it "gemfile/single_quot" do
    instance.detect("Gemfile", "gem 'sinatra'").should eq(true)
  end
  it "gemfile/double_quot" do
    instance.detect("Gemfile", "gem \"sinatra\"").should eq(true)
  end
end
