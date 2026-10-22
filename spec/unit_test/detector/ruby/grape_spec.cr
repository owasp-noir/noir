require "../../../spec_helper"
require "../../../../src/detector/detectors/ruby/*"

describe "Detect Ruby Grape" do
  options = create_test_options
  instance = Detector::Ruby::Grape.new options

  it "gemfile/single_quot" do
    instance.detect("Gemfile", "gem 'grape'").should be_true
  end
  it "gemfile/double_quot" do
    instance.detect("Gemfile", "gem \"grape\"").should be_true
  end
  it "rb/class_inherits_Grape::API" do
    instance.detect("app.rb", "class API < Grape::API\nend").should be_true
  end
  it "rb/require_grape" do
    instance.detect("app.rb", "require 'grape'").should be_true
  end
  it "rb/unrelated" do
    instance.detect("app.rb", "puts 'hi'").should be_false
  end
end
