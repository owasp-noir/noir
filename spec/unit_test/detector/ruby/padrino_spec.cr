require "../../../spec_helper"
require "../../../../src/detector/detectors/ruby/*"

describe "Detect Ruby Padrino" do
  options = create_test_options
  instance = Detector::Ruby::Padrino.new options

  it "gemfile/single_quot" do
    instance.detect("Gemfile", "gem 'padrino'").should be_true
  end
  it "gemfile/double_quot" do
    instance.detect("Gemfile", "gem \"padrino\"").should be_true
  end
  it "gemfile/padrino-core" do
    instance.detect("Gemfile", "gem 'padrino-core'").should be_true
  end
  it "gemfile/parenthesized call form" do
    instance.detect("Gemfile", "gem('padrino', '~> 0.15')").should be_true
  end
  it "gemfile/no_padrino_dep" do
    instance.detect("Gemfile", "gem 'sinatra'").should be_false
  end
  it "gemspec/add_dependency" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_dependency 'padrino-core', '~> 0.15'
      end
      RUBY
    instance.detect("foo.gemspec", contents).should be_true
  end
  it "gemspec/add_runtime_dependency" do
    contents = <<-RUBY
      Gem::Specification.new do |spec|
        spec.add_runtime_dependency "padrino", ">= 0.15"
      end
      RUBY
    instance.detect("foo.gemspec", contents).should be_true
  end
  it "gemspec/no_padrino_dep" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_dependency 'rails'
      end
      RUBY
    instance.detect("foo.gemspec", contents).should be_false
  end
  it "source/class_padrino_application" do
    contents = <<-RUBY
      class Blog < Padrino::Application
        get '/' do
          'hi'
        end
      end
      RUBY
    instance.detect("app/app.rb", contents).should be_true
  end
  it "source/padrino_mount" do
    contents = <<-RUBY
      Padrino.mount('blog').to('/blog')
      RUBY
    instance.detect("config/apps.rb", contents).should be_true
  end
  it "source/require_padrino_core" do
    instance.detect("app.rb", "require 'padrino-core'").should be_true
  end
  it "source/require_padrino" do
    instance.detect("app.rb", "require 'padrino'").should be_true
  end
  it "source/plain_sinatra_no_padrino_marker" do
    contents = <<-RUBY
      class Blog < Sinatra::Base
        get '/' do
          'hi'
        end
      end
      RUBY
    instance.detect("app.rb", contents).should be_false
  end
end
