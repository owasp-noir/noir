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

  it "reads an app-defined callback's body: a token decoder is no guard, a 401 is" do
    CodeLocator.instance.clear_all
    Dir.glob("#{fixture_base}/app/controllers/*.rb") { |path| CodeLocator.instance.register_path(path) }
    articles_path = "#{fixture_base}/app/controllers/articles_controller.rb"

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(fixture_base)
      # articles#index (line 4) inherits ApplicationController's
      # `before_action :authenticate_user`, whose body only decodes an
      # `Authorization` header when one is present.
      index = Endpoint.new("/articles", "GET", [] of Param, Details.new(PathInfo.new(articles_path, 4)))
      # posts#show (line 10) runs the app's own `authenticate_user!`, which
      # answers `head :unauthorized`.
      show = Endpoint.new("/posts/1", "GET", [] of Param, Details.new(PathInfo.new(controller_path, 10)))

      RubyAuthTagger.new(noir_options).perform([index, show])

      index.tags.should be_empty
      show.tags.map(&.description).should eq(["Protected by authenticate_user! (app-defined, rejects in its body)"])
    ensure
      CodeLocator.instance.clear_all
    end
  end

  it "reads a plainly named callback's 401/403 by what its condition checks" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("ruby_denying_callbacks")
    controllers = File.join(tmpdir, "app", "controllers")
    Dir.mkdir_p(controllers)
    files = {
      "platform_controller.rb" => <<-RB,
        class PlatformController < ActionController::API
          before_action :load_token
          before_action :set_platform_app

          private

          def load_token
            @access_token = AccessToken.find_by(token: request.headers['api_access_token'])
          end

          def set_platform_app
            @platform_app = @access_token.owner if @access_token
            render json: { error: 'Invalid access_token' }, status: :unauthorized if @platform_app.blank?
          end
        end
        RB
      "apps_controller.rb" => <<-RB,
        class AppsController < PlatformController
          def index
          end
        end
        RB
      "public_controller.rb" => <<-RB,
        class PublicController < ActionController::Base
          before_action :ensure_known_host
          before_action :ensure_active_account
          before_action :check_optional_token
          before_action :require_not_suspended!

          def index
          end

          private

          def ensure_known_host
            return if Domain.ours?(request.host)

            render json: { error: 'unknown domain' }, status: :unauthorized and return
          end

          def ensure_active_account
            @account = Account.find(params[:account_id])
            render json: { error: 'suspended' }, status: :unauthorized unless @account.active?
          end

          def check_optional_token
            return if request.headers['X-Token'].blank?

            head :unauthorized unless Token.valid?(request.headers['X-Token'])
          end

          # A 403 for a present-but-suspended user lets anonymous callers in.
          def require_not_suspended!
            render json: { error: 'disabled' }, status: 403 if current_user&.account&.unavailable?
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
      apps = Endpoint.new("/apps", "GET", [] of Param, Details.new(PathInfo.new(File.join(controllers, "apps_controller.rb"), 2)))
      public_index = Endpoint.new("/public", "GET", [] of Param, Details.new(PathInfo.new(File.join(controllers, "public_controller.rb"), 6)))

      RubyAuthTagger.new(noir_options).perform([apps, public_index])

      apps.tags.map(&.description).should eq(["Protected by set_platform_app (app-defined, refuses callers without a credential)"])
      public_index.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "reads a redirect or 4xx as a guard only when it fires for a caller the session did not log in" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("ruby_session_guards")
    controllers = File.join(tmpdir, "app", "controllers")
    Dir.mkdir_p(File.join(controllers, "concerns"))
    files = {
      "concerns/session_auth.rb" => <<-RB,
        module SessionAuth
          extend ActiveSupport::Concern

          included do
            before_action :load_session_user
          end

          def load_session_user
            if session[:u] && (user = User.find_by(session_token: session[:u].to_s))
              @user = user
            end
          end

          def require_logged_in_user
            if @user
              true
            else
              redirect_to "/login"
            end
          end

          def require_logged_in_user_or_400
            if @user
              true
            else
              render plain: "not logged in", status: 400
            end
          end

          def require_logged_in_moderator
            require_logged_in_user

            if @user
              if @user.is_moderator?
                true
              else
                redirect_to "/"
              end
            end
          end
        end
        RB
      "application_controller.rb" => <<-RB,
        class ApplicationController < ActionController::Base
          include SessionAuth
          before_action :check_read_only

          def check_read_only
            return redirect_to "/" if Rails.application.read_only?
          end

          def require_no_user_or_redirect
            redirect_to "/" if @user
          end

          def go_home
            cookies.delete(:x)
            redirect_to "/"
          end
        end
        RB
      "stories_controller.rb" => <<-RB,
        class StoriesController < ApplicationController
          before_action :require_logged_in_user_or_400,
            only: [:flag]
          before_action :require_logged_in_user, only: [:update]

          def show
          end

          def flag
          end

          def update
          end
        end
        RB
      "login_controller.rb" => <<-RB,
        class LoginController < ApplicationController
          before_action :require_no_user_or_redirect
          before_action :go_home, only: [:legacy]

          def create
          end

          def legacy
          end
        end
        RB
      "mod_controller.rb" => <<-RB,
        class ModController < ApplicationController
          before_action :require_logged_in_moderator

          def index
          end
        end
        RB
      "reports_controller.rb" => <<-RB,
        class ReportsController < ModController
          def index
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
      show, flag, update = at.call("stories_controller.rb", 6), at.call("stories_controller.rb", 9), at.call("stories_controller.rb", 12)
      login, legacy = at.call("login_controller.rb", 5), at.call("login_controller.rb", 8)
      mod, reports = at.call("mod_controller.rb", 4), at.call("reports_controller.rb", 2)

      RubyAuthTagger.new(noir_options).perform([show, flag, update, login, legacy, mod, reports])

      # `only:` on the continuation line limits the callback to `flag`.
      show.tags.should be_empty
      flag.tags.map(&.description).should eq(["Protected by require_logged_in_user_or_400 (app-defined, refuses callers without a credential)"])
      update.tags.map(&.description).should eq(["Protected by require_logged_in_user (app-defined, refuses callers without a credential)"])
      # Redirecting a logged-in user away, or everyone, is no guard.
      login.tags.should be_empty
      legacy.tags.should be_empty
      # The moderator check refuses anonymous callers through the call it makes.
      mod.tags.map(&.description).should eq(["Protected by require_logged_in_moderator (app-defined, refuses callers without a credential)"])
      reports.tags.map(&.description).should eq(["Protected by require_logged_in_moderator (app-defined, refuses callers without a credential)"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "reads an instance variable as the caller only by the assignment that runs for the request" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("ruby_caller_ivars")
    controllers = File.join(tmpdir, "app", "controllers")
    Dir.mkdir_p(controllers)
    files = {
      "application_controller.rb" => <<-RB,
        class ApplicationController < ActionController::Base
          before_action :load_session_user

          def load_session_user
            @user = User.find_by(id: session[:user_id]) if session[:user_id]
          end
        end
        RB
      # The looked-up profile owner, not the caller.
      "profiles_controller.rb" => <<-RB,
        class ProfilesController < ApplicationController
          before_action :find_profile_user

          def show
          end

          private

          def find_profile_user
            @user = User.find_by(username: params[:id])
            head :not_found unless @user
          end
        end
        RB
      # `@account = current_account` elsewhere does not make every `@account` the caller.
      "settings_controller.rb" => <<-RB,
        class SettingsController < ApplicationController
          before_action :set_account

          def set_account
            @account = current_account
          end
        end
        RB
      "subscriptions_controller.rb" => <<-RB,
        class SubscriptionsController < ApplicationController
          before_action :set_account
          before_action :require_account_permissions!

          def create
          end

          private

          def set_account
            @account = Account.local.find(params[:account_id])
          end

          def require_account_permissions!
            head 404 if @account.unavailable?
          end
        end
        RB
      # A deny that needs the user present lets anonymous callers through.
      "reports_controller.rb" => <<-RB,
        class ReportsController < ApplicationController
          before_action :kick_non_admins
          before_action :require_admin

          def index
          end

          private

          def kick_non_admins
            redirect_to root_path if current_user && !current_user.admin?
          end

          def require_admin
            if current_user
              redirect_to root_path unless current_user.admin?
            end
          end
        end
        RB
      # A comment after the comma, and an `only: [` closed lines later.
      "drafts_controller.rb" => <<-RB,
        class DraftsController < ApplicationController
          before_action :require_login, # writers only
            only: [:show]
          before_action :require_login, only: [
            :edit
          ]

          def index
          end

          def show
          end

          def edit
          end

          private

          def require_login
            redirect_to "/login" unless session[:user_id]
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
      profile, subscribe, reports = at.call("profiles_controller.rb", 4), at.call("subscriptions_controller.rb", 5), at.call("reports_controller.rb", 5)
      draft_index, draft_show, draft_edit = at.call("drafts_controller.rb", 8), at.call("drafts_controller.rb", 11), at.call("drafts_controller.rb", 14)

      RubyAuthTagger.new(noir_options).perform([profile, subscribe, reports, draft_index, draft_show, draft_edit])

      profile.tags.should be_empty
      subscribe.tags.should be_empty
      reports.tags.should be_empty
      draft_index.tags.should be_empty
      draft_show.tags.map(&.name).should eq(["auth"])
      draft_edit.tags.map(&.name).should eq(["auth"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "reads the controller callbacks through the handler when the route is declared in routes.rb" do
    CodeLocator.instance.clear_all
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)
    routes_path = "#{fixture_base}/config/routes.rb"
    articles_path = "#{fixture_base}/app/controllers/articles_controller.rb"

    feed = Endpoint.new("/articles/feed", "GET", [] of Param, Details.new(PathInfo.new(routes_path, 4)))
    feed.handler = Handler.new("articles#feed", articles_path, 12)
    index = Endpoint.new("/articles", "GET", [] of Param, Details.new(PathInfo.new(routes_path, 3)))
    index.handler = Handler.new("articles#index", articles_path, 4)

    RubyAuthTagger.new(noir_options).perform([feed, index])

    feed.tags.map(&.name).should eq(["auth"])
    feed.tags[0].description.should contain("authenticate_user!")
    index.tags.should be_empty
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

  it "reads lambda callbacks, optional-token and if: callbacks, and Pundit policies the way Rails runs them" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("ruby_lambda_callback")
    controllers = File.join(tmpdir, "app", "controllers")
    Dir.mkdir_p(File.join(controllers, "api"))
    Dir.mkdir_p(File.join(tmpdir, "app", "policies"))
    files = {
      # Mastodon's Api::BaseController
      "controllers/api/base_controller.rb" => <<-RB,
        class Api::BaseController < ApplicationController
          before_action :require_authenticated_user!, if: :disallow_unauthenticated_api_access?

          def require_authenticated_user!
            render json: { error: 'This method requires an authenticated user' }, status: 401 unless current_user
          end

          def require_user!
            render json: { error: 'Your login is currently disabled' }, status: 403 unless current_user
          end

          def authorize_if_got_token!(*scopes)
            doorkeeper_authorize!(*scopes) if doorkeeper_token
          end
        end
        RB
      "controllers/api/statuses_controller.rb" => <<-RB,
        class Api::StatusesController < Api::BaseController
          before_action -> { authorize_if_got_token! :read, :'read:statuses' }, except: [:create, :destroy]
          before_action -> { doorkeeper_authorize! :write, :'write:statuses' }, only: [:create, :destroy]
          before_action :require_user!, only: [:destroy]

          def index
          end

          def show
            authorize @status, :show?
          end

          def create
          end

          def destroy
            authorize @status, :destroy?
          end
        end
        RB
      "controllers/media_controller.rb" => <<-RB,
        class MediaController < ApplicationController
          before_action :authenticate_user!, if: :limited_federation_mode?

          def show
          end
        end
        RB
      "policies/status_policy.rb" => <<-RB,
        class StatusPolicy < ApplicationPolicy
          def show?
            current_account.nil? || !author.blocking?(current_account)
          end

          def destroy?
            owned?
          end
        end
        RB
    }
    files.each do |name, body|
      path = File.join(tmpdir, "app", name)
      File.write(path, body)
      CodeLocator.instance.register_path(path)
    end

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(name : String, line : Int32) do
        details = Details.new(PathInfo.new(File.join(controllers, name), line))
        details.technology = "ruby_rails"
        Endpoint.new("/#{name}/#{line}", "GET", [] of Param, details)
      end
      index = at.call("api/statuses_controller.rb", 6)
      show = at.call("api/statuses_controller.rb", 9)
      create = at.call("api/statuses_controller.rb", 13)
      destroy = at.call("api/statuses_controller.rb", 16)
      media = at.call("media_controller.rb", 4)

      RubyAuthTagger.new(noir_options).perform([index, show, create, destroy, media])

      # authorize_if_got_token! only checks scopes when a token was sent, and
      # the inherited `if:` callback is off by default; neither near
      # `doorkeeper_authorize!` reads as "Roda authorize!".
      index.tags.should be_empty
      show.tags.map { |t| {t.name, t.description} }.should eq([{"anonymous", "Pundit StatusPolicy#show? admits anonymous callers"}])
      create.tags.map(&.description).should eq(["Protected by Doorkeeper OAuth authorize"])
      destroy.tags.map(&.description).should eq(["Protected by require_user! (app-defined, rejects in its body)", "Protected by Pundit authorize"])
      media.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  # Doorkeeper's controllers are in the gem, not the scan: their
  # `authenticate_resource_owner!` / `authenticate_admin!` callbacks run the
  # blocks the app configures in its doorkeeper initializer.
  it "reads Doorkeeper base callbacks through the app's initializer blocks" do
    {
      # Mastodon's: an anonymous caller is sent to sign in; admin is a 403.
      {"current_user || redirect_to(new_user_session_url)", "head 403"} => {true, true},
      # Blocks that only look the caller up let anyone through.
      {"User.find_by(id: session[:user_id])", "current_user"} => {false, false},
    }.each do |(owner_block, admin_block), (owner_guarded, admin_guarded)|
      CodeLocator.instance.clear_all
      tmpdir = File.tempname("ruby_doorkeeper")
      controllers = File.join(tmpdir, "app", "controllers", "oauth")
      Dir.mkdir_p(controllers)
      Dir.mkdir_p(File.join(tmpdir, "config", "initializers"))
      files = {
        "config/initializers/doorkeeper.rb" => <<-RB,
          Doorkeeper.configure do
            resource_owner_authenticator do
              #{owner_block}
            end

            admin_authenticator do
              #{admin_block}
            end
          end
          RB
        "app/controllers/oauth/authorizations_controller.rb" => <<-RB,
          class OAuth::AuthorizationsController < Doorkeeper::AuthorizationsController
            prepend_before_action :store_current_location

            def new
              super
            end

            def authenticate_resource_owner!
              super
            end
          end
          RB
        "app/controllers/oauth/applications_controller.rb" => <<-RB,
          class OAuth::ApplicationsController < Doorkeeper::ApplicationsController
            def index
              super
            end
          end
          RB
      }
      files.each do |name, body|
        path = File.join(tmpdir, name)
        File.write(path, body)
        CodeLocator.instance.register_path(path)
      end

      begin
        noir_options = create_test_options
        noir_options["base"] = YAML::Any.new(tmpdir)
        at = ->(name : String, line : Int32) do
          details = Details.new(PathInfo.new(File.join(controllers, name), line))
          details.technology = "ruby_rails"
          Endpoint.new("/#{name}/#{line}", "GET", [] of Param, details)
        end
        authorize = at.call("authorizations_controller.rb", 4)
        applications = at.call("applications_controller.rb", 2)

        RubyAuthTagger.new(noir_options).perform([authorize, applications])

        authorize.tags.any? { |t| t.name == "auth" }.should eq(owner_guarded)
        applications.tags.any? { |t| t.name == "auth" }.should eq(admin_guarded)
      ensure
        FileUtils.rm_rf(tmpdir)
        CodeLocator.instance.clear_all
      end
    end
  end

  it "lists the methods a before_action line runs" do
    callbacks = ->(line : String) { Noir::RailsCallbackChain.before_action_callbacks(line) }
    callbacks.call("before_action :a!, :b?, only: :show").should eq(["a!", "b?"])
    callbacks.call("before_action -> { doorkeeper_authorize! :read, :'read:statuses' }, except: :create").should eq(["doorkeeper_authorize!"])
    callbacks.call("before_action ->(c) { c.authenticate_user! }").should eq([] of String)
    callbacks.call("before_action { authenticate_user! }").should eq(["authenticate_user!"])
    callbacks.call("before_action -> { authenticate_user! if limited? }").should eq([] of String)
    callbacks.call("skip_before_action :authenticate_user!").should eq([] of String)
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

describe "RubyAuthTagger (Sinatra route scope)" do
  it "reads the route's own body, not a guard helper's definition or earlier routes" do
    dir = File.tempname("noir_sinatra_auth")
    Dir.mkdir_p(dir)
    app = File.join(dir, "app.rb")
    File.write(app, <<-RB)
      require 'sinatra'

      helpers do
        def protected!
          return if authorized?
          halt 401, "Not authorized"
        end
      end

      get '/' do
        "public"
      end

      get '/protected' do
        protected!
        "secret"
      end

      get '/about' do
        "about"
      end
      RB

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(dir)
      at = ->(url : String, line : Int32) do
        details = Details.new(PathInfo.new(app, line))
        details.technology = "ruby_sinatra"
        Endpoint.new(url, "GET", [] of Param, details)
      end
      root = at.call("/", 10)
      protected_route = at.call("/protected", 14)
      about = at.call("/about", 19)

      RubyAuthTagger.new(noir_options).perform([root, protected_route, about])

      root.tags.should be_empty
      about.tags.should be_empty
      protected_route.tags.map(&.description).should eq(["Protected by protected! helper"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "applies a path-scoped before filter only to the routes it matches" do
    dir = File.tempname("noir_sinatra_before")
    Dir.mkdir_p(dir)
    app = File.join(dir, "app.rb")
    File.write(app, <<-RB)
      require 'sinatra'

      before '/admin/*' do
        protected!
      end

      get '/admin/panel' do
        "admin"
      end

      get '/public/health' do
        "ok"
      end
      RB

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(dir)
      at = ->(url : String, line : Int32) do
        details = Details.new(PathInfo.new(app, line))
        details.technology = "ruby_sinatra"
        Endpoint.new(url, "GET", [] of Param, details)
      end
      admin = at.call("/admin/panel", 7)
      health = at.call("/public/health", 11)

      RubyAuthTagger.new(noir_options).perform([admin, health])

      admin.tags.should_not be_empty
      health.tags.should be_empty
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end

describe "RubyAuthTagger (Grape route scope)" do
  it "reads an enclosing scope's filter past sibling routes, never a sibling scope's" do
    dir = File.tempname("noir_grape_scope")
    Dir.mkdir_p(dir)
    api = File.join(dir, "api.rb")
    # Each route below sits right after a line indented deeper than itself
    # (a continued `desc`), so the scope walk has to hop over deeper runs —
    # and `/open/ping` must not pick up the guard inside the sibling
    # `group :inner` block it hops over.
    File.write(api, <<-RB)
      class API < Grape::API
        namespace :admin do
          before { authenticate! }

          get '/first' do
            'a'
          end

          desc 'Users',
               hidden: true
          get '/users' do
            'b'
          end
        end

        namespace :open do
          group :inner do
            before { authenticate! }
            get '/x' do
              'x'
            end
          end

          desc 'Ping',
               hidden: true
          get '/ping' do
            'p'
          end
        end

        get '/health' do
          'ok'
        end
      end
      RB

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(dir)
      at = ->(url : String, line : Int32) do
        details = Details.new(PathInfo.new(api, line))
        details.technology = "ruby_grape"
        Endpoint.new(url, "GET", [] of Param, details)
      end
      users = at.call("/admin/users", 11)
      inner = at.call("/open/inner/x", 19)
      ping = at.call("/open/ping", 26)
      health = at.call("/health", 31)

      RubyAuthTagger.new(noir_options).perform([users, inner, ping, health])

      users.tags.map(&.description).should eq(["Protected by Grape authenticate!"])
      inner.tags.map(&.description).should eq(["Protected by Grape authenticate!"])
      ping.tags.should be_empty
      health.tags.should be_empty
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "reads a multi-line before do / authenticate! / end filter (#3317)" do
    dir = File.tempname("noir_grape_before_block")
    Dir.mkdir_p(dir)
    api = File.join(dir, "keys.rb")
    File.write(api, <<-RB)
      class Keys < Grape::API
        before do
          authenticate!
        end

        resource :keys do
          get do
            present []
          end
        end
      end

      class Open < Grape::API
        namespace :open do
          before do
            authenticate! if params[:private]
          end
          get :ping do
            'p'
          end
        end
      end
      RB

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(dir)
      at = ->(url : String, line : Int32) do
        details = Details.new(PathInfo.new(api, line))
        details.technology = "ruby_grape"
        Endpoint.new(url, "GET", [] of Param, details)
      end
      keys = at.call("/keys", 7)
      ping = at.call("/open/ping", 22)
      RubyAuthTagger.new(noir_options).perform([keys, ping])
      keys.tags.map(&.description).should eq(["Protected by Grape authenticate!"])
      # A conditional call admits callers when the condition is false.
      ping.tags.should be_empty
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end

describe "RubyAuthTagger (routed controller chain)" do
  it "reads a concern's action through the routed controller, a parent's Pundit callback and a setting-lifted guard" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("ruby_routed_chain")
    controllers = File.join(tmpdir, "app", "controllers")
    files = {
      "app/controllers/application_controller.rb" => <<-RB,
        class ApplicationController < ActionController::Base
          before_action :verify_private_site

          def verify_private_site
            return if user_signed_in? || Settings::Site.public
            head :unauthorized
          end
        end
        RB
      "app/controllers/api/base_controller.rb" => <<-RB,
        module Api
          class BaseController < ApplicationController
            def authenticate!
              head :unauthorized unless current_user
            end

            def validate_page_limit
              return if params[:page].to_i <= 1000
              return if current_user
              head :unauthorized
            end
          end
        end
        RB
      "app/controllers/concerns/api/articles_controller.rb" => <<-RB,
        module Api
          module ArticlesController
            extend ActiveSupport::Concern

            included do
              before_action :validate_page_limit, only: %i[index]
            end

            def index
            end

            def update
            end
          end
        end
        RB
      "app/controllers/api/v1/articles_controller.rb" => <<-RB,
        module Api
          module V1
            class ArticlesController < BaseController
              include Api::ArticlesController
              before_action :authenticate!, only: %i[update]
            end
          end
        end
        RB
      "app/controllers/admin/application_controller.rb" => <<-RB,
        module Admin
          class ApplicationController < ApplicationController
            before_action :authorize_admin

            def authorize_admin
              authorize(:dashboard, :access?, policy_class: InternalPolicy)
            end
          end
        end
        RB
      "app/controllers/admin/users_controller.rb" => <<-RB,
        module Admin
          class UsersController < Admin::ApplicationController
            def banish
            end
          end
        end
        RB
      "app/policies/internal_policy.rb" => <<-RB,
        class InternalPolicy < ApplicationPolicy
          def access?
            user.admin?
          end
        end
        RB
    }
    files.each do |name, body|
      path = File.join(tmpdir, name)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, body)
      CodeLocator.instance.register_path(path)
    end

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      concern = File.join(controllers, "concerns/api/articles_controller.rb")
      routed = ->(line : Int32) do
        endpoint = Endpoint.new("/api/articles/#{line}", "GET", [] of Param, Details.new(PathInfo.new(concern, line)))
        handler = Handler.new("articles#x", concern, line)
        handler.dispatch_path = File.join(controllers, "api/v1/articles_controller.rb")
        endpoint.handler = handler
        endpoint
      end
      index = routed.call(9)
      update = routed.call(12)
      banish = Endpoint.new("/admin/users/1/banish", "POST", [] of Param,
        Details.new(PathInfo.new(File.join(controllers, "admin/users_controller.rb"), 3)))

      RubyAuthTagger.new(noir_options).perform([index, update, banish])

      # A setting decides; the page-size check is the caller's own choice.
      index.tags.map(&.description).should eq(["Protected by verify_private_site (app-defined, refuses callers without a credential; `Settings::Site.public` decides; a setting can make it public)"])
      # The routed controller's `authenticate!` wins over the setting-lifted one.
      update.tags.map(&.description).should eq(["Protected by authenticate! (app-defined, refuses callers without a credential)"])
      # `class ApplicationController < ApplicationController` inside `Admin`
      # names the top-level one; its child's Pundit `authorize` callback guards.
      banish.tags.find { |t| t.name == "authz" }.should_not be_nil
      banish.tags.find! { |t| t.name == "auth" }.description.should contain("a setting can make it public")
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  # One `before_action` per controller, each guarding `index` (line 4) the
  # way its callback (at line 9 on) reads.
  it "judges request-value conditions, Pundit queries and early exits by what they let through" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("ruby_guard_definitions")
    controllers = File.join(tmpdir, "app", "controllers")
    callbacks = {
      # Both arms of the format branch deny: no value lets a caller in.
      "notes"   => "unless current_user\n  if params[:format] == \"json\"\n    head :unauthorized\n  else\n    redirect_to \"/login\"\n  end\nend",
      "memos"   => "return if params[:preview]\nhead :unauthorized unless current_user",
      "exports" => "if params[:access_code] != Rails.application.credentials.export_code && !current_user\n  head :forbidden\nend",
      "tags"    => "authorize Tag, :index?",
      "links"   => "authorize Link, :index?",
      "docs"    => "authorize Doc",
      "secrets" => "authorize(Secret, :index?)",
      "venues"  => "authorize Venue, :index? if current_user",
      "tickets" => "flash.now[:notice] = \"Please authorize the app\" unless cookies[:seen]",
    }
    policies = {
      "tag"    => "def index?\n    true\n  end",
      "link"   => "def index?\n    return true unless user\n\n    user.active?\n  end",
      "doc"    => "def index?\n    user.blank? || user.reader?\n  end",
      "secret" => "def index?\n    user.present? && user.admin?\n  end",
      "venue"  => "def index?\n    user.present?\n  end",
    }
    files = {
      "app/controllers/application_controller.rb" => <<-RB,
        class ApplicationController < ActionController::Base
          PUBLIC = %w[instances].freeze
          before_action :verify_private

          def verify_private
            return if controller_name.in?(PUBLIC)
            return if self.class.module_parent.to_s == "Admin"
            head :unauthorized unless current_user
          end
        end
        RB
      "app/controllers/instances_controller.rb"   => "class InstancesController < ApplicationController\n  def index\n  end\nend\n",
      "app/controllers/admin/stats_controller.rb" => "module Admin\n  class StatsController < ApplicationController\n    def index\n    end\n  end\nend\n",
      "app/controllers/plain_controller.rb"       => "class PlainController < ApplicationController\n  def index\n  end\nend\n",
    }
    callbacks.each do |name, body|
      kind = name.in?("notes", "memos", "exports") ? "ensure_member" : "authorize_#{name}"
      indented = body.lines.map { |l| "    #{l.chomp}" }.join("\n")
      files["app/controllers/#{name}_controller.rb"] = "class #{name.camelcase}Controller < ActionController::Base\n  before_action :#{kind}\n\n  def index\n  end\n\n  private\n\n  def #{kind}\n#{indented}\n  end\nend\n"
    end
    policies.each do |name, body|
      files["app/policies/#{name}_policy.rb"] = "class #{name.camelcase}Policy\n  def initialize(user, record)\n    @user = user\n  end\n\n  #{body}\nend\n"
    end
    files.each do |name, body|
      path = File.join(tmpdir, name)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, body)
      CodeLocator.instance.register_path(path)
    end

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      endpoints = callbacks.keys.map do |name|
        Endpoint.new("/#{name}", "GET", [] of Param, Details.new(PathInfo.new(File.join(controllers, "#{name}_controller.rb"), 4)))
      end
      instances = Endpoint.new("/instances", "GET", [] of Param, Details.new(PathInfo.new(File.join(controllers, "instances_controller.rb"), 2)))
      stats = Endpoint.new("/admin/stats", "GET", [] of Param, Details.new(PathInfo.new(File.join(controllers, "admin/stats_controller.rb"), 3)))
      plain = Endpoint.new("/plain", "GET", [] of Param, Details.new(PathInfo.new(File.join(controllers, "plain_controller.rb"), 2)))

      RubyAuthTagger.new(noir_options).perform(endpoints + [instances, stats, plain])

      guarded = (endpoints + [instances, stats, plain]).select { |e| e.tags.any?(&.name.in?("auth", "authz")) }.map(&.url)
      guarded.should eq(["/notes", "/exports", "/secrets", "/plain"])
      endpoints.find! { |e| e.url == "/secrets" }.tags.first.description.should contain("SecretPolicy#index?")
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "reads an inherited action through the routed controller's own skips" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("ruby_routed_skips")
    controllers = File.join(tmpdir, "app", "controllers")
    files = {
      "application_controller.rb"  => "class ApplicationController < ActionController::Base\nend\n",
      "items_base_controller.rb"   => "class ItemsBaseController < ApplicationController\n  before_action :authenticate_user!\n\n  def index\n  end\n\n  def show\n  end\nend\n",
      "public_items_controller.rb" => "class PublicItemsController < ItemsBaseController\n  skip_before_action :authenticate_user!\nend\n",
      "only_items_controller.rb"   => "class OnlyItemsController < ItemsBaseController\n  skip_before_action :authenticate_user!, only: [:show]\nend\n",
      "cond_items_controller.rb"   => "class CondItemsController < ItemsBaseController\n  skip_before_action :authenticate_user!, if: -> { Setting.public_items? }\nend\n",
      "format_items_controller.rb" => "class FormatItemsController < ItemsBaseController\n  skip_before_action :authenticate_user!, if: -> { request.format.json? }\nend\n",
    }
    files.each do |name, body|
      path = File.join(controllers, name)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, body)
      CodeLocator.instance.register_path(path)
    end

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      base = File.join(controllers, "items_base_controller.rb")
      routed = ->(controller : String, line : Int32) do
        endpoint = Endpoint.new("/#{controller}/#{line}", "GET", [] of Param, Details.new(PathInfo.new(base, line)))
        handler = Handler.new("#{controller}#x", base, line)
        handler.dispatch_path = File.join(controllers, "#{controller}_controller.rb")
        endpoint.handler = handler
        endpoint
      end
      public_index = routed.call("public_items", 4)
      only_index = routed.call("only_items", 4)
      only_show = routed.call("only_items", 7)
      cond_index = routed.call("cond_items", 4)
      format_index = routed.call("format_items", 4)

      RubyAuthTagger.new(noir_options).perform([public_index, only_index, only_show, cond_index, format_index])

      public_index.tags.should be_empty
      only_index.tags.map(&.name).should eq(["auth"])
      only_show.tags.should be_empty
      # An app setting decides the skip; the request format is the caller's.
      cond_index.tags.first.description.should contain("a setting can make it public")
      format_index.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "reads CanCanCan authorize_resource against the ability's rules for a nil user, and hash-rocket only:" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("ruby_cancan")
    files = {
      "app/controllers/application_controller.rb" => <<-RB,
        class ApplicationController < ActionController::Base
          rescue_from CanCan::AccessDenied, :with => :deny_access

          def current_ability
            Ability.new(current_user)
          end
        end
        RB
      "app/controllers/api_controller.rb" => <<-RB,
        class ApiController < ApplicationController
          def authorize
            setup_user_auth
            render :plain => "no", :status => :unauthorized unless current_user
          end

          def current_ability
            ApiAbility.new(current_user, scopes)
          end
        end
        RB
      "app/controllers/api/notes_controller.rb" => <<-RB,
        module Api
          class NotesController < ApiController
            before_action :authorize, :only => [:close]

            authorize_resource

            def search
            end

            def create
            end

            def close
            end

            def destroy
            end
          end
        end
        RB
      "app/controllers/api/notes/downloads_controller.rb" => <<-RB,
        module Api
          module Notes
            class DownloadsController < ApiController
              authorize_resource :note

              def show
              end
            end
          end
        end
        RB
      "app/controllers/issues_controller.rb" => <<-RB,
        class IssuesController < ApplicationController
          authorize_resource

          def index
          end

          def resolve
          end
        end
        RB
      "app/controllers/sections_controller.rb" => <<-RB,
        class SectionsController < ApplicationController
          authorize_resource :class => :profile

          def show
          end

          def update
          end
        end
        RB
      "app/controllers/descriptions_controller.rb" => <<-RB,
        class DescriptionsController < SectionsController
          skip_authorize_resource :only => :show
        end
        RB
      "app/models/ability.rb" => <<-RB,
        class Ability
          include CanCan::Ability

          def initialize(user)
            can :read, Issue if Settings.status != "offline"

            if user&.active?
              can [:read, :update], [:preferences, :profile]
              can :resolve, Issue if user.moderator?
            end
          end
        end
        RB
      "app/abilities/api_ability.rb" => <<-RB,
        class ApiAbility
          include CanCan::Ability

          def initialize(user, scopes)
            can [:read, :search], Note
            can :create, Note unless user

            if user
              can [:create, :close], Note if scopes.include?("write_notes")
            end
            can :destroy, Note if scopes.include?("moderate")
          end
        end
        RB
    }
    paths = files.to_h do |name, body|
      path = File.join(tmpdir, name)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, body)
      CodeLocator.instance.register_path(path)
      {name, path}
    end

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(name : String, line : Int32, routed : String?) do
        path = paths[name]
        endpoint = Endpoint.new("/#{File.basename(name, ".rb")}/#{line}", "GET", [] of Param, Details.new(PathInfo.new(path, line)))
        handler = Handler.new("x#y", path, line)
        handler.dispatch_path = paths[routed] if routed
        endpoint.handler = handler
        endpoint
      end
      notes = "app/controllers/api/notes_controller.rb"
      search, create, close, destroy = at.call(notes, 7, nil), at.call(notes, 10, nil), at.call(notes, 13, nil), at.call(notes, 16, nil)
      download = at.call("app/controllers/api/notes/downloads_controller.rb", 6, nil)
      issues = "app/controllers/issues_controller.rb"
      index, resolve = at.call(issues, 4, nil), at.call(issues, 7, nil)
      sections = "app/controllers/sections_controller.rb"
      update = at.call(sections, 7, "app/controllers/descriptions_controller.rb")
      show = at.call(sections, 4, "app/controllers/descriptions_controller.rb")
      endpoints = [search, create, close, destroy, download, index, resolve, update, show]

      RubyAuthTagger.new(noir_options).perform(endpoints)

      # Granted to everyone, `unless user`, behind a setting, or to the
      # parent `:note` resource's `:show`: open. `:only => [:close]` keeps
      # `authorize` off the other actions.
      [search, create, download, index, show].each(&.tags.should(be_empty))
      close.tags.map(&.description).should contain("Protected by authorize")
      resolve.tags.first.description.should contain("CanCanCan authorize_resource (Ability grants :resolve on Issue to no nil user)")
      update.tags.first.description.should contain("grants :update on :profile")
      # A rule under a condition the reader cannot judge is not a refusal.
      destroy.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "judges CanCanCan rule conditions per class or record check, and keeps guards behind opaque only:/skip lists" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("ruby_cancan_conditions")
    ctrl = ->(name : String, macro_line : String) do
      "class #{name.camelcase}Controller < ApplicationController\n  #{macro_line}\n  def index; end\n  def show; end\n  def update; end\nend\n"
    end
    files = {
      "app/controllers/application_controller.rb" => "class ApplicationController < ActionController::Base\nend\n",
      "app/controllers/notes_controller.rb"       => ctrl.call("notes", "load_and_authorize_resource"),
      "app/controllers/posts_controller.rb"       => ctrl.call("posts", "authorize_resource"),
      "app/controllers/people_controller.rb"      => ctrl.call("people", "load_and_authorize_resource"),
      "app/controllers/quizzes_controller.rb"     => ctrl.call("quizzes", "load_and_authorize_resource"),
      "app/controllers/drafts_controller.rb"      => ctrl.call("drafts", "load_and_authorize_resource"),
      "app/controllers/secrets_controller.rb"     => ctrl.call("secrets", "load_and_authorize_resource"),
      "app/controllers/b1_controller.rb"          => "class B1Controller < ApplicationController\n  before_action :require_login, only: PROTECTED\n  skip_before_action :require_login, :only => PUBLIC\n  def index; end\n\n  def require_login\n    head :unauthorized unless current_user\n  end\nend\n",
      "app/models/ability.rb"                     => <<-RB,
        class Ability
          include CanCan::Ability

          def initialize(user)
            can :read, Note, user_id: user.id
            can :update, Post, user_id: user.id
            can :read, [Person, Quiz]
            can :read, Draft
            cannot :read, Draft
            can :read, Secret
            cannot :read, Secret, hidden: true
          end
        end
        RB
      # Not the app's ability: a spec helper and another engine's.
      "spec/support/ability.rb"              => "class Ability\n  include CanCan::Ability\n\n  def initialize(user)\n    return unless user\n    can :manage, :all\n  end\nend\n",
      "engines/legacy/app/models/ability.rb" => "class Ability\n  include CanCan::Ability\n\n  def initialize(user)\n  end\nend\n",
    }
    paths = files.to_h do |name, body|
      path = File.join(tmpdir, name)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, body)
      CodeLocator.instance.register_path(path)
      {name, path}
    end

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(controller : String, url : String, line : Int32) do
        path = paths["app/controllers/#{controller}_controller.rb"]
        endpoint = Endpoint.new(url, "GET", [] of Param, Details.new(PathInfo.new(path, line)))
        endpoint.handler = Handler.new("x#y", path, line)
        endpoint
      end
      note_index, note_show = at.call("notes", "/notes", 3), at.call("notes", "/notes/:id", 4)
      post_update = at.call("posts", "/posts/:id", 5)
      people, quizzes = at.call("people", "/people/:id", 4), at.call("quizzes", "/quizzes", 3)
      draft, secret = at.call("drafts", "/drafts/:id", 4), at.call("secrets", "/secrets/:id", 4)
      b1 = at.call("b1", "/b1", 4)
      endpoints = [note_index, note_show, post_update, people, quizzes, draft, secret, b1]

      RubyAuthTagger.new(noir_options).perform(endpoints)

      # A class check ignores conditions; a loaded record must match the
      # caller, which a nil user does not. Bare `authorize_resource`
      # checks the class.
      note_index.tags.should be_empty
      note_show.tags.first.description.should contain("grants :show on Note to no nil user")
      post_update.tags.should be_empty
      # Irregular plurals name the rule's model.
      people.tags.should be_empty
      quizzes.tags.should be_empty
      # An unconditional `cannot` wins; a conditioned one refuses some records only.
      draft.tags.first.description.should contain("on Draft")
      secret.tags.should be_empty
      # `only: PROTECTED` runs for every action; `skip ..., :only => PUBLIC` for none.
      b1.tags.map(&.name).should eq(["auth"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "reads a guest user object's caller conditions on a record as unknown" do
    ability = Noir::CanCanAbility.new(<<-RB.lines)
      class Ability
        include CanCan::Ability

        def initialize(user)
          user ||= User.new
          can :read, Note, user_id: user.id
          can :manage, :all if user.admin?
        end
      end
      RB
    ability.verdict("index", "Note").yes?.should be_true
    ability.verdict("show", "Note", instance: true).maybe?.should be_true
    ability.verdict("destroy", "Note", instance: true).no?.should be_true
    # A subject no rule names (`:all` aside) may be misread: unknown.
    Noir::CanCanAbility.new("class A\n  include CanCan::Ability\n\n  def initialize(user)\n    can :read, Note\n  end\nend\n".lines).verdict("show", "Medium").maybe?.should be_true
  end
end
