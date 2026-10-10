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

  it "inherits auth callbacks from parent controllers and concerns" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("ruby_inherited_auth")
    controllers = File.join(tmpdir, "app", "controllers")
    Dir.mkdir_p(File.join(controllers, "concerns"))
    Dir.mkdir_p(File.join(controllers, "admin"))
    files = {
      # Rails 8 `rails generate authentication`
      "concerns/authentication.rb" => <<-RB,
        module Authentication
          extend ActiveSupport::Concern

          included do
            before_action :require_authentication
          end

          class_methods do
            def allow_unauthenticated_access(**options)
              skip_before_action :require_authentication, **options
            end
          end
        end
        RB
      "application_controller.rb" => <<-RB,
        class ApplicationController < ActionController::Base
          include Authentication
        end
        RB
      "sessions_controller.rb" => <<-RB,
        class SessionsController < ApplicationController
          allow_unauthenticated_access only: %i[ new create ]

          def create
          end

          def destroy
          end
        end
        RB
      "posts_controller.rb" => <<-RB,
        class PostsController < ApplicationController
          def index
          end
        end
        RB
      # Devise in a namespaced base controller
      "admin/base_controller.rb" => <<-RB,
        module Admin
          class BaseController < ::ApplicationController
            allow_unauthenticated_access
            before_action :authenticate_user!, except: :ping
          end
        end
        RB
      "admin/reports_controller.rb" => <<-RB,
        module Admin
          class ReportsController < BaseController
            skip_before_action :authenticate_user!, only: [:feed]

            def index
            end

            def feed
            end

            def ping
            end
          end
        end
        RB
    }
    files.each do |name, body|
      path = File.join(controllers, name)
      File.write(path, body)
      CodeLocator.instance.register_path(path)
    end

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(name : String, line : Int32) do
        Endpoint.new("/#{name}/#{line}", "GET", [] of Param, Details.new(PathInfo.new(File.join(controllers, name), line)))
      end
      session_create = at.call("sessions_controller.rb", 4)
      session_destroy = at.call("sessions_controller.rb", 7)
      posts_index = at.call("posts_controller.rb", 2)
      reports_index = at.call("admin/reports_controller.rb", 5)
      reports_feed = at.call("admin/reports_controller.rb", 8)
      reports_ping = at.call("admin/reports_controller.rb", 11)

      RubyAuthTagger.new(noir_options).perform([session_create, session_destroy, posts_index, reports_index, reports_feed, reports_ping])

      session_create.tags.should be_empty
      session_destroy.tags.map(&.description).should eq(["Protected by require_authentication"])
      posts_index.tags.map(&.description).should eq(["Protected by require_authentication"])
      reports_index.tags.map(&.description).should eq(["Protected by Devise authenticate_user!"])
      reports_feed.tags.should be_empty
      reports_ping.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "treats skip_before_action as an opt-out, never as the callback it skips" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("ruby_skip_callback")
    controllers = File.join(tmpdir, "app", "controllers")
    Dir.mkdir_p(File.join(controllers, "api"))
    files = {
      "api/base_controller.rb" => <<-RB,
        module Api
          class BaseController < ActionController::API
            before_action :doorkeeper_authorize!
          end
        end
        RB
      "api/users_controller.rb" => <<-RB,
        module Api
          class UsersController < BaseController
            skip_before_action :doorkeeper_authorize!, only: [:index]

            def index
            end

            def show
            end
          end
        end
        RB
      "posts_controller.rb" => <<-RB,
        class PostsController < ActionController::API
          before_action :doorkeeper_authorize!
          skip_before_action :doorkeeper_authorize!, only: [:index]

          def index
          end

          def show
          end
        end
        RB
    }
    files.each do |name, body|
      path = File.join(controllers, name)
      File.write(path, body)
      CodeLocator.instance.register_path(path)
    end

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(name : String, line : Int32) do
        Endpoint.new("/#{name}/#{line}", "GET", [] of Param, Details.new(PathInfo.new(File.join(controllers, name), line)))
      end
      users_index = at.call("api/users_controller.rb", 5)
      users_show = at.call("api/users_controller.rb", 8)
      posts_index = at.call("posts_controller.rb", 5)
      posts_show = at.call("posts_controller.rb", 8)

      RubyAuthTagger.new(noir_options).perform([users_index, users_show, posts_index, posts_show])

      users_index.tags.should be_empty
      users_show.tags.map(&.description).should eq(["Protected by Doorkeeper OAuth authorize"])
      posts_index.tags.should be_empty
      posts_show.tags.map(&.description).should eq(["Protected by Doorkeeper OAuth authorize"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
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
