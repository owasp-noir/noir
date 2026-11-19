require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Fixture line references
#
# webhooks_controller.rb
#   1: class WebhooksController < ApplicationController
#   2:   skip_before_action :verify_authenticity_token
#   3:   rate_limit to: 10, within: 1.minute, only: :create
#   5:   def create
#  10:   def index
#
# users_controller.rb
#   1: class UsersController < ApplicationController
#   2:   protect_from_forgery with: :null_session
#   3:   skip_before_action :verify_authenticity_token, only: [:create]
#   5:   def index
#   9:   def create   ->  user = User.new(params[:user])
#  15:   def update   ->  user.update(params.permit!)
#
# exports_controller.rb (rate_limit with its only: on the next line)
#   5:   def show
#   8:   def create
#
# posts_controller.rb (control: default CSRF + Strong Parameters)
#   2:   def index
#   6:   def create   ->  Post.new(post_params)

private def tag_named(endpoint : Endpoint, name : String) : Tag?
  endpoint.tags.find { |t| t.name == name }
end

private def build_endpoint(path : String, line : Int32, method : String = "POST") : Endpoint
  details = Details.new(PathInfo.new(path, line))
  details.technology = "ruby_rails"
  Endpoint.new("/x", method, [] of Param, details)
end

describe "RailsSecurityTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/ruby/rails_security", __DIR__)
  webhooks = "#{fixture_base}/app/controllers/webhooks_controller.rb"
  users = "#{fixture_base}/app/controllers/users_controller.rb"
  posts = "#{fixture_base}/app/controllers/posts_controller.rb"
  exports = "#{fixture_base}/app/controllers/exports_controller.rb"

  options = create_test_options
  options["base"] = YAML::Any.new(fixture_base)

  it "exposes ruby_rails as its only target tech" do
    RailsSecurityTagger.target_techs.should eq(["ruby_rails"])
  end

  describe "csrf-protection" do
    it "flags skip_before_action :verify_authenticity_token (disabled)" do
      endpoint = build_endpoint(webhooks, 5)
      RailsSecurityTagger.new(options).perform([endpoint])

      tag = tag_named(endpoint, "csrf-protection")
      tag.should_not be_nil
      tag.not_nil!.tagger.should eq("rails_security")
      tag.not_nil!.description.should contain("disabled")
    end

    it "flags protect_from_forgery with: :null_session (downgraded)" do
      endpoint = build_endpoint(users, 5) # index, only inherits null_session
      RailsSecurityTagger.new(options).perform([endpoint])

      tag = tag_named(endpoint, "csrf-protection")
      tag.should_not be_nil
      tag.not_nil!.description.should contain("null_session")
    end

    it "honours only: so the skip applies just to the named action" do
      # create is in only: [:create] -> disabled (nearest macro wins)
      create_ep = build_endpoint(users, 9)
      RailsSecurityTagger.new(options).perform([create_ep])
      tag_named(create_ep, "csrf-protection").not_nil!.description.should contain("disabled")

      # update is not in only: [:create] -> falls through to null_session
      update_ep = build_endpoint(users, 15)
      RailsSecurityTagger.new(options).perform([update_ep])
      tag_named(update_ep, "csrf-protection").not_nil!.description.should contain("null_session")
    end

    it "reads the controller through the handler when the route is anchored in routes.rb" do
      routes = "#{fixture_base}/config/routes.rb"
      endpoint = build_endpoint(routes, 4)
      endpoint.handler = Handler.new("webhooks#create", webhooks, 5)
      RailsSecurityTagger.new(options).perform([endpoint])
      tag_named(endpoint, "csrf-protection").should_not be_nil
      tag_named(endpoint, "rate-limit").should_not be_nil
    end

    it "does not flag a GET action, which Rails never CSRF-verifies" do
      endpoint = build_endpoint(webhooks, 10, "GET") # index
      RailsSecurityTagger.new(options).perform([endpoint])
      tag_named(endpoint, "csrf-protection").should be_nil
    end

    it "does not flag a controller relying on the Rails default" do
      endpoint = build_endpoint(posts, 2) # index
      RailsSecurityTagger.new(options).perform([endpoint])
      tag_named(endpoint, "csrf-protection").should be_nil
    end

    it "reads a CSRF macro a parent controller or concern declares, unless the child re-enables it" do
      CodeLocator.instance.clear_all
      dir = File.tempname("noir_rails_csrf_chain")
      files = {
        "app/controllers/application_controller.rb" => "class ApplicationController < ActionController::Base\nend\n",
        "app/controllers/api/base_controller.rb"    => "module Api\n  class BaseController < ApplicationController\n    skip_before_action :verify_authenticity_token, only: [:create]\n  end\nend\n",
        "app/controllers/api/items_controller.rb"   => "module Api\n  class ItemsController < BaseController\n    def update\n    end\n\n    def create\n    end\n  end\nend\n",
        "app/controllers/api/notes_controller.rb"   => "module Api\n  class NotesController < BaseController\n    protect_from_forgery with: :exception\n\n    def create\n    end\n  end\nend\n",
        "app/controllers/concerns/token_api.rb"     => "module TokenApi\n  extend ActiveSupport::Concern\n\n  included do\n    protect_from_forgery with: :null_session\n  end\nend\n",
        "app/controllers/tokens_controller.rb"      => "class TokensController < ApplicationController\n  include TokenApi\n\n  def create\n  end\nend\n",
        "app/controllers/hooks_controller.rb"       => "class LegacyHooksController < ApplicationController\n  skip_forgery_protection\nend\n\nclass HooksController < ApplicationController\n  def create\n  end\nend\n",
      }
      begin
        files.each do |rel, body|
          Dir.mkdir_p(File.dirname(File.join(dir, rel)))
          File.write(File.join(dir, rel), body)
          CodeLocator.instance.register_path(File.join(dir, rel))
        end
        chain_options = create_test_options
        chain_options["base"] = YAML::Any.new(dir)
        items = "#{dir}/app/controllers/api/items_controller.rb"
        item_create = build_endpoint(items, 6)
        item_update = build_endpoint(items, 3)
        note_create = build_endpoint("#{dir}/app/controllers/api/notes_controller.rb", 5)
        token_create = build_endpoint("#{dir}/app/controllers/tokens_controller.rb", 4)
        hook_create = build_endpoint("#{dir}/app/controllers/hooks_controller.rb", 6)
        RailsSecurityTagger.new(chain_options).perform([item_create, item_update, note_create, token_create, hook_create])

        tag_named(item_create, "csrf-protection").not_nil!.description.should contain("disabled")
        # A POST action the parent's `only:` leaves out keeps its CSRF check.
        tag_named(item_update, "csrf-protection").should be_nil
        tag_named(note_create, "csrf-protection").should be_nil
        tag_named(token_create, "csrf-protection").not_nil!.description.should contain("null_session")
        # A sibling class earlier in the file is not the routed controller.
        tag_named(hook_create, "csrf-protection").should be_nil
      ensure
        FileUtils.rm_rf(dir)
        CodeLocator.instance.clear_all
      end
    end
  end

  describe "rate-limit" do
    it "flags a rate_limit macro scoped to the action via only:" do
      endpoint = build_endpoint(webhooks, 5) # create (only: :create)
      RailsSecurityTagger.new(options).perform([endpoint])

      tag = tag_named(endpoint, "rate-limit")
      tag.should_not be_nil
      tag.not_nil!.tagger.should eq("rails_security")
    end

    it "does not flag an action outside the rate_limit only: filter" do
      endpoint = build_endpoint(webhooks, 10) # index
      RailsSecurityTagger.new(options).perform([endpoint])
      tag_named(endpoint, "rate-limit").should be_nil
    end
  end

  it "reads a rate_limit only: continued on the next line" do
    show = build_endpoint(exports, 5, "GET")
    create = build_endpoint(exports, 8)
    RailsSecurityTagger.new(options).perform([show, create])
    tag_named(show, "rate-limit").should be_nil
    tag_named(create, "rate-limit").should_not be_nil
  end

  describe "mass-assignment" do
    it "flags a raw params hash passed to a model writer" do
      endpoint = build_endpoint(users, 9) # User.new(params[:user])
      RailsSecurityTagger.new(options).perform([endpoint])

      tag = tag_named(endpoint, "mass-assignment")
      tag.should_not be_nil
      tag.not_nil!.description.should contain("model writer")
    end

    it "flags params.permit!" do
      endpoint = build_endpoint(users, 15) # user.update(params.permit!)
      RailsSecurityTagger.new(options).perform([endpoint])

      tag = tag_named(endpoint, "mass-assignment")
      tag.should_not be_nil
      tag.not_nil!.description.should contain("permit!")
    end

    it "does not flag a strong-parameters action" do
      endpoint = build_endpoint(posts, 6) # Post.new(post_params)
      RailsSecurityTagger.new(options).perform([endpoint])
      tag_named(endpoint, "mass-assignment").should be_nil
    end
  end

  it "applies multiple independent tags to one action" do
    endpoint = build_endpoint(webhooks, 5) # create: CSRF disabled + rate limited
    RailsSecurityTagger.new(options).perform([endpoint])

    tag_named(endpoint, "csrf-protection").should_not be_nil
    tag_named(endpoint, "rate-limit").should_not be_nil
  end
end
