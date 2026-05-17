require "../../../spec_helper"
require "../../../../src/detector/detectors/ruby/*"

describe "Detect Ruby Rails" do
  options = create_test_options
  instance = Detector::Ruby::Rails.new options

  it "gemfile/single_quot" do
    instance.detect("Gemfile", "gem 'rails'").should be_true
  end
  it "gemfile/double_quot" do
    instance.detect("Gemfile", "gem \"rails\"").should be_true
  end
  it "gemfile/railties_single_quot" do
    instance.detect("Gemfile", "gem 'railties', '~> 8.0.0'").should be_true
  end
  it "gemfile/railties_double_quot" do
    instance.detect("Gemfile", "gem \"railties\", \"~> 8.0.0\"").should be_true
  end
  it "gemfile/no_rails_components" do
    instance.detect("Gemfile", "gem 'sinatra'\ngem 'rack'").should be_false
  end
end
