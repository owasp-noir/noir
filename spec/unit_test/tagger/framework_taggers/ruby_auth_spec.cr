require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "RubyAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/ruby/rails_auth"
  controller_path = "#{fixture_base}/app/controllers/posts_controller.rb"

  # posts_controller.rb line reference:
  #  1: class PostsController < ApplicationController
  #  2:   before_action :authenticate_user!
  #  3:   skip_before_action :authenticate_user!, only: [:index]
  #  5:   def index
  #  9:   def show
  # 13:   def create
  # 18:   def destroy

  it "detects before_action :authenticate_user! on protected action" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 9))
    details.technology = "ruby_rails"
    endpoint = Endpoint.new("/posts/1", "GET", [] of Param, details)

    tagger = RubyAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("ruby_auth")
    endpoint.tags[0].description.should contain("authenticate_user")
  end

  it "detects Pundit authorize in action body" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 13))
    details.technology = "ruby_rails"
    endpoint = Endpoint.new("/posts", "POST", [] of Param, details)

    tagger = RubyAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
  end

  it "respects skip_before_action for :index" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 5))
    details.technology = "ruby_rails"
    endpoint = Endpoint.new("/posts", "GET", [] of Param, details)

    tagger = RubyAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end
