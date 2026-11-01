require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Shapes from a Rails app whose callbacks split "read a credential if one
# was sent" from "refuse a caller who sent none", plus an anti-forgery
# callback every visitor passes.
private def tag_actions(files : Hash(String, String), routes : Array({String, String, Int32})) : Hash(String, Array(String))
  auth_tags(files, routes).transform_values(&.map(&.description))
end

private def auth_tags(files : Hash(String, String), routes : Array({String, String, Int32})) : Hash(String, Array(Tag))
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("ruby_auth_optional")
  files.each do |name, body|
    path = File.join(tmpdir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, body)
    CodeLocator.instance.register_path(path)
  end
  begin
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    endpoints = routes.map { |url, file, line| Endpoint.new(url, "POST", [] of Param, Details.new(PathInfo.new(File.join(tmpdir, file), line))) }
    RubyAuthTagger.new(noir_options).perform(endpoints)
    endpoints.to_h { |ep| {ep.url, ep.tags.select { |t| t.name == "auth" }} }
  ensure
    FileUtils.rm_rf(tmpdir)
    CodeLocator.instance.clear_all
  end
end

APP_CONTROLLER = <<-RB
  class ApplicationController < ActionController::Base
    include ApplicationController::Authenticates
    include ApplicationController::PreventsCsrf
  end
  RB

AUTHENTICATES = <<-RB
  module ApplicationController::Authenticates
    extend ActiveSupport::Concern

    private

    def authentication_check
      user = authentication_check_only
      if !user
        raise Exceptions::Forbidden, 'Authentication required'
      end
      true
    end

    def authentication_check_only
      errors = []
      if session.id && session[:user_id]
        user = User.lookup(id: session[:user_id])
        return check_prerequisites(user) if user
        errors.push('no user')
      end

      authenticate_with_http_basic do |username, password|
        auth = Auth.new(username, password)
        begin
          auth.valid!
          return check_prerequisites(auth.user)
        rescue Auth::Error::AuthenticationFailed
          errors.push('bad basic')
        end
      end

      return false if errors.blank?

      raise Exceptions::NotAuthorized, errors.join(', ')
    end

    def check_prerequisites(user)
      raise Exceptions::NotAuthorized, 'inactive' if !user.active || Auth::SwitchedSession.revoked?(session[:switched_from])
      current_user_set(user)
    end
  end
  RB

PREVENTS_CSRF = <<-RB
  module ApplicationController::PreventsCsrf
    extend ActiveSupport::Concern

    included do
      before_action :verify_csrf_token
    end

    private

    def verify_csrf_token
      return true if request.get? || request.head?
      return true if %w[token_auth basic_auth].include?(@_auth_type)
      return true if valid_authenticity_token?(session, params[:authenticity_token] || request.headers['X-CSRF-Token'])

      raise Exceptions::InvalidCSRFToken
    end
  end
  RB

describe "RubyAuthTagger (optional credential readers)" do
  it "reads an optional credential reader as open and the check that refuses its nil result as a guard" do
    tags = tag_actions({
      "app/controllers/application_controller.rb"               => APP_CONTROLLER,
      "app/controllers/application_controller/authenticates.rb" => AUTHENTICATES,
      "app/controllers/application_controller/prevents_csrf.rb" => PREVENTS_CSRF,
      "app/controllers/signups_controller.rb"                   => <<-RB,
        class SignupsController < ApplicationController
          prepend_before_action :authentication_check_only

          def create
            render json: {}
          end
        end
        RB
      "app/controllers/tickets_controller.rb" => <<-RB,
        class TicketsController < ApplicationController
          prepend_before_action :authentication_check

          def create
            render json: {}
          end
        end
        RB
      "app/controllers/feeds_controller.rb" => <<-RB,
        class FeedsController < ApplicationController
          prepend_before_action { authentication_check(basic_auth_prompt: true) && authorize! }

          def create
            render json: {}
          end
        end
        RB
      "app/controllers/forms_controller.rb" => <<-RB,
        class FormsController < ApplicationController
          def create
            render json: {}
          end
        end
        RB
    }, [
      {"/signups", "app/controllers/signups_controller.rb", 4},
      {"/tickets", "app/controllers/tickets_controller.rb", 4},
      {"/feeds", "app/controllers/feeds_controller.rb", 4},
      {"/forms", "app/controllers/forms_controller.rb", 2},
    ])

    tags["/signups"].should be_empty
    tags["/forms"].should be_empty
    tags["/tickets"].should eq(["Protected by authentication_check (app-defined, refuses callers without a credential)"])
    tags["/feeds"].should eq(["Protected by authentication_check (app-defined, refuses callers without a credential)"])
  end

  it "points a guard tag at the callback's definition" do
    tags = auth_tags({
      "app/controllers/application_controller.rb"               => APP_CONTROLLER,
      "app/controllers/application_controller/authenticates.rb" => AUTHENTICATES,
      "app/controllers/application_controller/prevents_csrf.rb" => PREVENTS_CSRF,
      "app/controllers/tickets_controller.rb"                   => "class TicketsController < ApplicationController\n  prepend_before_action :authentication_check\n\n  def create\n  end\nend\n",
    }, [{"/tickets", "app/controllers/tickets_controller.rb", 4}])
    tag = tags["/tickets"].first
    tag.path.to_s.should end_with("application_controller/authenticates.rb")
    tag.line.should eq(6)
  end

  it "keeps the guards those readings must not lose" do
    tags = tag_actions({
      "app/controllers/application_controller.rb"               => APP_CONTROLLER,
      "app/controllers/application_controller/authenticates.rb" => AUTHENTICATES,
      "app/controllers/application_controller/prevents_csrf.rb" => PREVENTS_CSRF,
      "app/controllers/guests_controller.rb"                    => <<-RB,
        class GuestsController < ApplicationController
          before_action :refuse_signed_in

          def create
            render json: {}
          end

          private

          def refuse_signed_in
            user = authentication_check_only
            raise Exceptions::Forbidden, 'already signed in' if user
          end
        end
        RB
      "app/controllers/strict_controller.rb" => <<-RB,
        class StrictController < ApplicationController
          before_action :strict_reader

          def create
            render json: {}
          end

          private

          def strict_reader
            errors = []
            errors.push('no credential')
            if session[:user_id]
              user = User.lookup(id: session[:user_id])
              return check_prerequisites(user) if user
            end
            return false if errors.blank?

            raise Exceptions::NotAuthorized, errors.join(', ')
          end
        end
        RB
      "app/controllers/mixed_controller.rb" => <<-RB,
        class MixedController < ApplicationController
          before_action :verify_user_and_token

          def create
            render json: {}
          end

          private

          def verify_user_and_token
            head :unauthorized unless current_user && valid_authenticity_token?(session, params[:authenticity_token])
          end
        end
        RB
    }, [
      {"/guests", "app/controllers/guests_controller.rb", 4},
      {"/strict", "app/controllers/strict_controller.rb", 4},
      {"/mixed", "app/controllers/mixed_controller.rb", 4},
    ])

    # Refuses a caller who is signed in, never an anonymous one.
    tags["/guests"].should be_empty
    # `errors` is filled for every caller, so the exit never lets one out.
    tags["/strict"].size.should eq(1)
    # The forgery token is only half of the deny; `current_user` is the other.
    tags["/mixed"].size.should eq(1)
  end

  it "reads a skip macro a concern defines under class_methods" do
    concern = <<-RB
      module Authentication
        extend ActiveSupport::Concern

        included do
          before_action :authenticate_user!
        end

        class_methods do
          def skip_authentication(**options)
            skip_before_action :authenticate_user!, **options
          end
        end

        private
          def authenticate_user!
            redirect_to new_session_url unless find_session_by_cookie
          end

          def find_session_by_cookie
            Session.find_by(id: cookies.signed[:session_token])
          end
      end
      RB
    tags = tag_actions({
      "app/controllers/concerns/authentication.rb" => concern,
      "app/controllers/application_controller.rb"  => <<-RB,
        class ApplicationController < ActionController::Base
          include Authentication
        end
        RB
      "app/controllers/sessions_controller.rb" => <<-RB,
        class SessionsController < ApplicationController
          skip_authentication only: %i[new create]

          def create
            render json: {}
          end

          def destroy
            render json: {}
          end
        end
        RB
      "app/controllers/webhooks_controller.rb" => <<-RB,
        class WebhooksController < ApplicationController
          skip_authentication

          def create
            render json: {}
          end
        end
        RB
    }, [
      {"/sessions", "app/controllers/sessions_controller.rb", 4},
      {"/sessions/1", "app/controllers/sessions_controller.rb", 8},
      {"/webhooks", "app/controllers/webhooks_controller.rb", 4},
    ])

    tags["/sessions"].should be_empty
    tags["/webhooks"].should be_empty
    # Not in the skip's `only:` list.
    tags["/sessions/1"].size.should eq(1)
  end

  it "keeps a guard whose forgery check or empty-errors exit only a signed-in caller reaches" do
    callbacks = {
      # The CSRF exit sits under `if current_user`: anonymous gets the 401.
      "csrf_nested"       => "if current_user\n  return if valid_authenticity_token?(session, request.headers['X-CSRF-Token'])\nend\nhead :unauthorized",
      "csrf_nested_raise" => "if current_user\n  return if valid_authenticity_token?(session, params[:authenticity_token])\nend\nraise Exceptions::NotAuthorized",
      # A forgery word in the deny itself, but it waits on `current_user`.
      "csrf_word_redirect" => "redirect_to new_session_path(csrf_failed: true) unless current_user",
      "csrf_word_raise"    => "raise Exceptions::InvalidCSRFToken unless current_user",
      # A forgery exit above, but the deny's own condition is the caller.
      "csrf_exit_then_user" => "return if request.get?\nreturn if valid_authenticity_token?(session, params[:authenticity_token])\nraise Exceptions::NotAuthorized unless current_user",
      # `errors` filled for an anonymous caller outside any credential branch.
      "errors_plus"    => "errors = []\nif session[:user_id]\n  return true if User.find_by(id: session[:user_id])\n  errors.push('no user')\nend\nerrors += ['authentication required'] unless session[:user_id]\nreturn false if errors.blank?\nraise Exceptions::NotAuthorized, errors.join(', ')",
      "errors_helper"  => "errors = []\nif session[:user_id]\n  return true if User.find_by(id: session[:user_id])\n  errors.push('no user')\nend\nrequire_credential(errors)\nreturn false if errors.blank?\nraise Exceptions::NotAuthorized, errors.join(', ')",
      "errors_unshift" => "errors = []\nif session[:user_id]\n  return true if User.find_by(id: session[:user_id])\n  errors.push('no user')\nend\nerrors.unshift('authentication required') unless session[:user_id]\nreturn false if errors.blank?\nraise Exceptions::NotAuthorized",
    }
    files = {
      "app/controllers/application_controller.rb" => <<-RB,
        class ApplicationController < ActionController::Base
          def require_credential(errors)
            errors << 'authentication required' if session[:user_id].nil?
          end
        end
        RB
    }
    routes = [] of {String, String, Int32}
    callbacks.each do |name, body|
      indented = body.lines.map { |line| "    #{line}" }.join("\n")
      files["app/controllers/#{name}_controller.rb"] = "class #{name.camelcase}Controller < ApplicationController\n  before_action :check\n\n  def create\n    render json: {}\n  end\n\n  private\n\n  def check\n#{indented}\n  end\nend\n"
      routes << {"/#{name}", "app/controllers/#{name}_controller.rb", 4}
    end
    tags = tag_actions(files, routes)
    callbacks.each_key { |name| {name, tags["/#{name}"].size}.should eq({name, 1}) }
  end

  it "reads a reader that looks up something other than the caller as no credential" do
    tags = tag_actions({
      "app/controllers/application_controller.rb" => "class ApplicationController < ActionController::Base\nend\n",
      "app/controllers/carts_controller.rb"       => <<-RB,
        class CartsController < ApplicationController
          before_action :load_cart

          def create
            render json: {}
          end

          private

          def load_cart
            cart = current_cart
            redirect_to root_path, alert: 'Your cart is empty' unless cart
          end

          def current_cart
            Cart.find_by(id: session[:cart_id])
          end
        end
        RB
    }, [{"/carts", "app/controllers/carts_controller.rb", 4}])
    tags["/carts"].should be_empty
  end

  it "keeps a guard a skip macro lifts only on a condition" do
    concern_with = ->(body : String) do
      <<-RB
        module Authentication
          extend ActiveSupport::Concern

          included do
            before_action :authenticate_user!
          end

          class_methods do
            def skip_authentication(**options)
        #{body}
            end
          end

          private

          def authenticate_user!
            redirect_to new_session_path unless session[:user_id]
          end
        end
        RB
    end
    {
      "test_only" => "      skip_before_action :authenticate_user!, **options if Rails.env.test?",
      "setting"   => "      if Rails.configuration.x.public_signup\n        skip_before_action :authenticate_user!, **options\n      end",
    }.each do |label, body|
      tags = tag_actions({
        "app/controllers/concerns/authentication.rb" => concern_with.call(body),
        "app/controllers/application_controller.rb"  => "class ApplicationController < ActionController::Base\n  include Authentication\nend\n",
        "app/controllers/things_controller.rb"       => "class ThingsController < ApplicationController\n  skip_authentication only: [:create]\n\n  def create\n    render json: {}\n  end\nend\n",
      }, [{"/things", "app/controllers/things_controller.rb", 4}])
      {label, tags["/things"].size}.should eq({label, 1})
    end
  end

  it "reads a long run of empty-errors exits in near-linear time" do
    time_for = ->(n : Int32) do
      body = String.build do |io|
        io << "    errors = []\n    errors << 'x'\n"
        n.times { |k| io << "    return if errors.blank?\n    raise Forbidden unless session[:u#{k}]\n" }
      end
      files = {
        "app/controllers/application_controller.rb" => "class ApplicationController < ActionController::Base\nend\n",
        "app/controllers/things_controller.rb"      => "class ThingsController < ApplicationController\n  before_action :check\n\n  def create\n    render json: {}\n  end\n\n  private\n\n  def check\n#{body}  end\nend\n",
      }
      Time.measure { tag_actions(files, [{"/things", "app/controllers/things_controller.rb", 4}]) }
    end
    time_for.call(50)
    small = time_for.call(150)
    large = time_for.call(600)
    # 4x the lines; a cubic walk takes ~64x, so allow well under that.
    (large / small).should be < 32
  end
end
