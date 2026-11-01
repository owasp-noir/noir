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
end
