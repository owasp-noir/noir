require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "RubyAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/ruby/rails_auth", __DIR__)
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

    details = Details.new(PathInfo.new(controller_path, 10))
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

    details = Details.new(PathInfo.new(controller_path, 14))
    details.technology = "ruby_rails"
    endpoint = Endpoint.new("/posts", "POST", [] of Param, details)

    tagger = RubyAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags.any? { |t| t.name == "authz" && t.description.includes?("authorize") }.should be_true
  end

  it "stacks Devise authenticate_user! with Pundit authorize" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 14))
    details.technology = "ruby_rails"
    endpoint = Endpoint.new("/posts", "POST", [] of Param, details)

    tagger = RubyAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.map(&.name).sort!.should eq(["auth", "authz"])
    endpoint.tags.find! { |t| t.name == "auth" }.description.should contain("authenticate_user")
    endpoint.tags.find! { |t| t.name == "authz" }.description.should contain("authorize")
  end

  it "respects skip_before_action for :index" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 6))
    details.technology = "ruby_rails"
    endpoint = Endpoint.new("/posts", "GET", [] of Param, details)

    tagger = RubyAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "keeps action-body authorize when authenticate is skipped" do
    tmpdir = File.tempname("ruby_skip_authz")
    Dir.mkdir_p(tmpdir)
    path = File.join(tmpdir, "posts_controller.rb")
    File.write(path, [
      "class PostsController < ApplicationController",
      "  before_action :authenticate_user!",
      "  skip_before_action :authenticate_user!, only: [:index]",
      "",
      "  def index",
      "    post = Post.find(params[:id])",
      "    authorize post",
      "    render json: post",
      "  end",
      "end",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    details = Details.new(PathInfo.new(path, 5))
    details.technology = "ruby_rails"
    endpoint = Endpoint.new("/posts", "GET", [] of Param, details)

    RubyAuthTagger.new(noir_options).perform([endpoint])

    endpoint.tags.map(&.name).should eq(["authz"])
    endpoint.tags[0].description.should contain("authorize")

    FileUtils.rm_rf(tmpdir)
  end
end

# Additional tests for Grape + Roda support (B target)
describe "RubyAuthTagger (Grape/Roda)" do
  grape_base = File.expand_path("../../../functional_test/fixtures/ruby/grape", __DIR__)
  grape_path = "#{grape_base}/app.rb"

  roda_base = File.expand_path("../../../functional_test/fixtures/ruby/roda", __DIR__)
  roda_path = "#{roda_base}/app.rb"

  it "detects Grape before { authenticate! } and helpers" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(grape_base)

    details = Details.new(PathInfo.new(grape_path, 81)) # admin/dashboard get with before
    details.technology = "ruby_grape"
    endpoint = Endpoint.new("/admin/dashboard", "GET", [] of Param, details)

    tagger = RubyAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("ruby_auth")
  end

  it "detects Roda rodauth.require_authentication and logged_in?" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(roda_base)

    details = Details.new(PathInfo.new(roda_path, 58)) # dashboard route with rodauth.require_authentication
    details.technology = "ruby_roda"
    endpoint = Endpoint.new("/dashboard", "GET", [] of Param, details)

    tagger = RubyAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("ruby_auth")
    endpoint.tags[0].description.should match(/Rodauth|rodauth/i)
  end
end
