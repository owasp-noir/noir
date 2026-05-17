require "../../../spec_helper"
require "../../../../src/detector/detectors/ruby/*"

describe "Detect Ruby Hanami" do
  options = create_test_options
  instance = Detector::Ruby::Hanami.new options

  it "gemfile/single_quot" do
    instance.detect("Gemfile", "gem 'hanami'").should be_true
  end
  it "gemfile/double_quot" do
    instance.detect("Gemfile", "gem \"hanami\"").should be_true
  end
  it "gemspec/add_dependency" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_dependency 'hanami', '~> 2.0'
      end
      RUBY
    instance.detect("my_app.gemspec", contents).should be_true
  end
  it "gemspec/no_hanami_dep" do
    contents = <<-RUBY
      Gem::Specification.new do |spec|
        spec.name = "hanami"
        spec.add_dependency 'dry-system'
      end
      RUBY
    instance.detect("hanami.gemspec", contents).should be_false
  end
end
