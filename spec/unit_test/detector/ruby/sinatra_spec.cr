require "../../../spec_helper"
require "../../../../src/detector/detectors/ruby/*"

describe "Detect Ruby Sinatra" do
  options = create_test_options
  instance = Detector::Ruby::Sinatra.new options

  it "gemfile/single_quot" do
    instance.detect("Gemfile", "gem 'sinatra'").should be_true
  end
  it "gemfile/double_quot" do
    instance.detect("Gemfile", "gem \"sinatra\"").should be_true
  end
end
