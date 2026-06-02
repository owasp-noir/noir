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

  it "gemspec/add_dependency_rails" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.name = "spree_core"
        s.add_dependency 'rails', '>= 7.2', '< 8.2'
      end
      RUBY
    instance.detect("spree/core/spree_core.gemspec", contents).should be_true
  end

  it "gemspec/add_dependency_railties" do
    contents = <<-RUBY
      Gem::Specification.new do |spec|
        spec.add_dependency "railties", "~> 8.0.0"
      end
      RUBY
    instance.detect("foo.gemspec", contents).should be_true
  end

  it "gemspec/add_runtime_dependency" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_runtime_dependency 'rails', '~> 7.0'
      end
      RUBY
    instance.detect("legacy.gemspec", contents).should be_true
  end

  it "gemspec/no_rails_dependency" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_dependency 'sinatra'
        s.add_dependency 'rack'
      end
      RUBY
    instance.detect("sinatra-thing.gemspec", contents).should be_false
  end

  it "gemspec/add_dependency parenthesized call form" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_dependency('railties', "~> 8.0")
      end
      RUBY
    instance.detect("engine.gemspec", contents).should be_true
  end

  it "gemfile/does not match jquery-rails" do
    instance.detect("Gemfile", "gem 'jquery-rails'\ngem 'sinatra'").should be_false
  end
end
