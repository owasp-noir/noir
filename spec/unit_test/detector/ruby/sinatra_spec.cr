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
  it "gemspec/add_dependency" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_dependency 'sinatra', '~> 4.0'
      end
      RUBY
    instance.detect("gollum.gemspec", contents).should be_true
  end
  it "gemspec/add_runtime_dependency" do
    contents = <<-RUBY
      Gem::Specification.new do |spec|
        spec.add_runtime_dependency "sinatra", ">= 2.0"
      end
      RUBY
    instance.detect("foo.gemspec", contents).should be_true
  end
  it "gemspec/no_sinatra_dep" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_dependency 'rails'
      end
      RUBY
    instance.detect("foo.gemspec", contents).should be_false
  end
  it "gemspec/add_dependency parenthesized call form (geminabox)" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_dependency('sinatra', "~> 4.0")
      end
      RUBY
    instance.detect("geminabox.gemspec", contents).should be_true
  end
  it "gemfile/parenthesized call form" do
    instance.detect("Gemfile", "gem('sinatra', '~> 4.0')").should be_true
  end
  it "gemspec/does not match sinatra-contrib" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_dependency 'sinatra-contrib'
      end
      RUBY
    instance.detect("foo.gemspec", contents).should be_false
  end
end
