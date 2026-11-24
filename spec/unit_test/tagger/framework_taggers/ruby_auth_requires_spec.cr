require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Each clause's atoms; clauses read from two callbacks may repeat.
private def requirement(tag : Tag) : Array(Array(String))
  Access.of(tag).map(&.any_of.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s }).uniq!
end

# Writes `files` under a fresh app, tags one endpoint per `{file, line}` and
# returns each endpoint's ruby_auth tags by name.
private def tag_app(files : Hash(String, String), at : Array({String, Int32})) : Array(Hash(String, Tag))
  CodeLocator.instance.clear_all
  dir = File.tempname("noir_ruby_requires")
  files.each do |name, body|
    path = File.join(dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, body)
    CodeLocator.instance.register_path(path)
  end
  begin
    options = create_test_options
    options["base"] = YAML::Any.new(dir)
    endpoints = at.map do |file, line|
      details = Details.new(PathInfo.new(File.join(dir, file), line))
      details.technology = "ruby_rails"
      Endpoint.new("/#{file}/#{line}", "GET", [] of Param, details)
    end
    RubyAuthTagger.new(options).perform(endpoints)
    endpoints.map { |endpoint| endpoint.tags.select(&.tagger.==("ruby_auth")).to_h { |tag| {tag.name, tag} } }
  ensure
    FileUtils.rm_rf(dir)
    CodeLocator.instance.clear_all
  end
end

APP_BASE = <<-RB
  class ApplicationController < ActionController::Base
    before_action :authenticate_user!
  end
  RB

describe "RubyAuthTagger requires" do
  it "reads Devise authenticate_user! as signed in and a Pundit query as the app's" do
    tags = tag_app({
      "app/controllers/application_controller.rb" => APP_BASE,
      "app/controllers/posts_controller.rb"       => <<-RB,
        class PostsController < ApplicationController
          def update
            @post = Post.find(params[:id])
            authorize @post, :publish?
          end
        end
        RB
    }, [{"app/controllers/posts_controller.rb", 2}]).first

    requirement(tags["auth"]).should eq([["authenticated"]])
    tags["auth"].requires.not_nil!.first.source.should eq("before_action :authenticate_user!")
    requirement(tags["authz"]).should eq([["unresolved:PostPolicy#publish?"]])
  end

  it "keeps a Devise scope other than user unresolved, with its name in the source" do
    tags = tag_app({
      "app/controllers/admin_controller.rb" => <<-RB,
        class AdminController < ActionController::Base
          before_action :authenticate_admin!

          def index
          end
        end
        RB
    }, [{"app/controllers/admin_controller.rb", 4}]).first

    requirement(tags["auth"]).should eq([["authenticated"], ["unresolved:authenticate_admin!"]])
    tags["auth"].requires.not_nil!.map(&.source).uniq!.should eq(["before_action :authenticate_admin!"])
  end

  it "adds a parent's guard and a child's to the requirement, and reads a literal Rolify role" do
    tags = tag_app({
      "app/controllers/application_controller.rb" => APP_BASE,
      "app/controllers/reports_controller.rb"     => <<-RB,
        class ReportsController < ApplicationController
          before_action :require_admin

          def index
          end

          private

          def require_admin
            redirect_to root_path unless current_user && current_user.has_role?(:admin)
          end
        end
        RB
    }, [{"app/controllers/reports_controller.rb", 4}]).first

    tags["auth"].description.should eq("Protected by Devise authenticate_user!")
    requirement(tags["auth"]).should eq([["authenticated"], ["unresolved:require_admin"]])
    requirement(tags["authz"]).should eq([["authenticated"], ["role:admin"]])
  end

  it "keeps a role callback's other refusals unresolved" do
    tags = tag_app({
      "app/controllers/application_controller.rb" => APP_BASE,
      "app/controllers/audits_controller.rb"      => <<-RB,
        class AuditsController < ApplicationController
          before_action :require_auditor

          def index
          end

          private

          def require_auditor
            head :forbidden unless current_user.active?
            head :forbidden unless current_user.has_role?(:auditor)
          end
        end
        RB
    }, [{"app/controllers/audits_controller.rb", 4}]).first

    requirement(tags["authz"]).should eq([["role:auditor"], ["unresolved:require_auditor"]])
  end

  it "keeps a parent's unread check when the child names Devise" do
    tags = tag_app({
      "app/controllers/application_controller.rb" => <<-RB,
        class ApplicationController < ActionController::Base
          before_action :check_session

          def check_session
            head :unauthorized unless session[:user_id]
          end
        end
        RB
      "app/controllers/notes_controller.rb" => <<-RB,
        class NotesController < ApplicationController
          before_action :authenticate_user!

          def index
          end
        end
        RB
    }, [{"app/controllers/notes_controller.rb", 4}]).first

    tags["auth"].description.should eq("Protected by Devise authenticate_user!")
    requirement(tags["auth"]).should eq([["authenticated"], ["unresolved:check_session"]])
  end

  it "keeps what a conditional skip, an unless: or an if: guard lets past as an alternative" do
    tagged = tag_app({
      "app/controllers/application_controller.rb" => <<-RB,
        class ApplicationController < ActionController::Base
          before_action :authenticate_user!, unless: :api_request?
        end
        RB
      "app/controllers/devise_app_controller.rb" => <<-RB,
        class DeviseAppController < ActionController::Base
          before_action :authenticate_user!, unless: :devise_controller?
          before_action :require_staff, if: :staff_area?

          def index
          end

          def require_staff
            head :forbidden unless current_user && current_user.has_role?(:staff)
          end
        end
        RB
      "app/controllers/previews_controller.rb" => <<-RB,
        class PreviewsController < ActionController::Base
          before_action :authenticate_user!
          skip_before_action :authenticate_user!, if: -> { Flipper.enabled?(:public_previews) }

          def show
          end
        end
        RB
      "app/controllers/items_controller.rb" => <<-RB,
        class ItemsController < ApplicationController
          def index
          end
        end
        RB
    }, [{"app/controllers/items_controller.rb", 2}, {"app/controllers/devise_app_controller.rb", 5}, {"app/controllers/previews_controller.rb", 5}])
    items, devise_app, previews = tagged

    requirement(items["auth"]).should eq([["authenticated", "unresolved:unless: :api_request?"]])
    requirement(devise_app["auth"]).should eq([
      ["authenticated"],
      ["authenticated", "unresolved:if: :staff_area?"],
      ["unresolved:if: :staff_area?", "unresolved:require_staff"],
      ["role:staff", "unresolved:if: :staff_area?"],
    ])
    previews["auth"].description.should contain("a setting can make it public")
    requirement(previews["auth"]).should eq([["authenticated", "unresolved:if: -> { Flipper.enabled?(:public_previews) }"]])
  end

  it "reads a CanCanCan symbol action only from a statement every request reaches, beside a guest's grant" do
    tagged = tag_app({
      "app/controllers/application_controller.rb" => APP_BASE,
      "app/models/ability.rb"                     => <<-RB,
        class Ability
          include CanCan::Ability

          def initialize(user)
            can :read, Post

            if user&.active?
              can :publish, Post
            end
          end
        end
        RB
      "app/controllers/posts_controller.rb" => <<-RB,
        class PostsController < ApplicationController
          def show
            @post = Post.find(params[:id])
            authorize! :read, @post
          end

          def edit
            return redirect_to(root_path) if params[:preview]
            authorize! :update, @post
          end

          def destroy
            authorize! :destroy, @post if @post.locked?
          end

          def publish
            authorize! :publish, @post
          end
        end
        RB
    }, [{"app/controllers/posts_controller.rb", 2}, {"app/controllers/posts_controller.rb", 7}, {"app/controllers/posts_controller.rb", 12}, {"app/controllers/posts_controller.rb", 16}])
    show, edit, destroy, publish = tagged

    requirement(show["authz"]).should eq([["permission:read", "unresolved:whether the ability grants :read to a guest"]])
    requirement(publish["authz"]).should eq([["permission:publish"]])
    show["authz"].requires.not_nil!.first.source.should eq("authorize! :read, @post")
    requirement(edit["authz"]).should eq([["unresolved:authorize! :update, @post"]])
    requirement(destroy["authz"]).should eq([["unresolved:authorize! :destroy, @post if @post.locked?"]])
  end

  it "keeps a CanCanCan resource macro and a parent outside the scan unresolved" do
    tagged = tag_app({
      "app/controllers/products_controller.rb" => <<-RB,
        class ProductsController < Spree::BaseController
          before_action :authenticate_user!
          load_and_authorize_resource

          def index
          end
        end
        RB
    }, [{"app/controllers/products_controller.rb", 5}])

    requirement(tagged.first["auth"]).should eq([
      ["authenticated"],
      ["unresolved:load_and_authorize_resource"],
      ["unresolved:callbacks of Spree::BaseController, a parent class noir did not read"],
    ])
  end

  it "reads a Doorkeeper block callback as signed in with its scopes unread" do
    tags = tag_app({
      "app/controllers/api_controller.rb" => <<-RB,
        class ApiController < ActionController::API
          before_action -> { doorkeeper_authorize! :read, :write }

          def index
          end
        end
        RB
    }, [{"app/controllers/api_controller.rb", 4}]).first

    requirement(tags["auth"]).should eq([["authenticated"], ["unresolved:doorkeeper_authorize!"]])
  end

  it "reads Devise route blocks" do
    tagged = tag_app({
      "config/routes.rb" => <<-RB,
        Rails.application.routes.draw do
          authenticate :user do
            get "/blazer", to: "blazer#index"
          end
          authenticated :admin, ->(u) { u.super? } do
            get "/jobs", to: "jobs#index"
          end
        end
        RB
    }, [{"config/routes.rb", 3}, {"config/routes.rb", 6}])
    blazer, jobs = tagged

    requirement(blazer["auth"]).should eq([["authenticated"]])
    requirement(jobs["auth"]).should eq([
      ["authenticated"],
      ["unresolved:authenticated :admin, ->(u) { u.super? }"],
      ["unresolved:authenticated (a routing constraint: other callers fall through to the next matching route)"],
    ])
  end
end
