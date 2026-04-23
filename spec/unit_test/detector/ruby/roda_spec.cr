require "../../../spec_helper"
require "../../../../src/detector/detectors/ruby/*"

describe "Detect Ruby Roda" do
  options = create_test_options
  instance = Detector::Ruby::Roda.new options

  it "gemfile/single_quot" do
    instance.detect("Gemfile", "gem 'roda'").should be_true
  end
  it "gemfile/double_quot" do
    instance.detect("Gemfile", "gem \"roda\"").should be_true
  end
  it "app.rb/class_inherit" do
    instance.detect("app.rb", "class App < Roda\nend").should be_true
  end
  it "app.rb/require" do
    instance.detect("app.rb", "require \"roda\"").should be_true
  end
  it "app.rb/roda_route" do
    instance.detect("app.rb", "Roda.route { |r| }").should be_true
  end
  it "non-roda" do
    instance.detect("Gemfile", "gem 'sinatra'").should be_false
  end
end
