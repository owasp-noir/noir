require "../../spec_helper"
require "../../../src/miniparsers/rails_callback_chain"

private def build_chain(files : Hash(String, String), controllers : Array(String)) : Noir::RailsCallbackChain
  others = files.keys - controllers
  Noir::RailsCallbackChain.build(controllers, others) { |path| files[path]? }
end

describe Noir::RailsCallbackChain do
  it "expands a class macro its ancestry defines, with the call's options" do
    files = {
      "/app/controllers/application_controller.rb" => <<-RB,
        class ApplicationController < ActionController::Base
          def self.requires_login(arg = {})
            before_action :ensure_logged_in, arg
          end
        end
        RB
      "/app/controllers/drafts_controller.rb" => <<-RB,
        class DraftsController < ApplicationController
          requires_login except: [:index]
        end
        RB
      # Another app's macro of the same name is not this class's.
      "/other/app/controllers/base_controller.rb" => <<-RB,
        class BaseController
          def self.requires_login(arg = {})
            before_action :other_login, arg
          end
        end
        RB
    }
    chain = build_chain(files, files.keys)
    drafts = chain.controller_in("/app/controllers/drafts_controller.rb").should_not be_nil
    chain.resolve(drafts, "destroy").callbacks.should eq(["ensure_logged_in"])
    chain.resolve(drafts, "destroy").settings.should eq(Set{"requires_login"})
    chain.resolve(drafts, "index").callbacks.should be_empty
    chain.resolve(drafts, "index").settings.should be_empty
  end

  it "never lets a `def self.before_action` override hide the callbacks it registers" do
    files = {
      "/app/controllers/application_controller.rb" => <<-RB,
        class ApplicationController < ActionController::Base
          def self.before_action(*names, **opts)
            Rails.logger.debug(names)
            super
          end

          before_action :authenticate_user!
        end
        RB
    }
    chain = build_chain(files, files.keys)
    app = chain.controller_in("/app/controllers/application_controller.rb").should_not be_nil
    chain.resolve(app, "index").callbacks.should eq(["authenticate_user!"])
  end

  it "loads included modules from lib/, nearest namespace first and transitively" do
    files = {
      "/app/controllers/admin/uploads_controller.rb" => <<-RB,
        module Admin
          class UploadsController < ApplicationController
            include UploadHelpers
          end
        end
        RB
      "/lib/admin/upload_helpers.rb" => <<-RB,
        module Admin
          module UploadHelpers
            include ExternalAuth
            def create_multipart
            end
          end
        end
        RB
      "/lib/external_auth.rb" => <<-RB,
        module ExternalAuth
          before_action :check_external_token
        end
        RB
      "/lib/unrelated.rb" => "module Unrelated\nend\n",
    }
    chain = build_chain(files, ["/app/controllers/admin/uploads_controller.rb"])
    uploads = chain.controller_in("/app/controllers/admin/uploads_controller.rb").should_not be_nil
    resolved = chain.resolve(uploads, "create_multipart")
    resolved.callbacks.should eq(["check_external_token"])
    resolved.paths.should contain("/lib/admin/upload_helpers.rb")
    chain.defs.has_key?("create_multipart").should be_true
    chain.controller_in("/lib/unrelated.rb").should be_nil
    chain.classes.values.none?(&.name.==("Unrelated")).should be_true
  end

  describe "reading class bodies off the AST" do
    callbacks = ->(body : String, action : String) do
      chain = build_chain({"/app/controllers/c_controller.rb" => "class CController < ActionController::Base\n#{body}\nend\n"}, ["/app/controllers/c_controller.rb"])
      chain.resolve(chain.controller_in("/app/controllers/c_controller.rb").not_nil!, action)
    end

    it "reads `:only =>` and `%i[]` the way it reads `only: [...]`" do
      callbacks.call("before_action :a, :only => [:show]\nbefore_action :b, only: %i[edit show]", "show").callbacks.should eq(["a", "b"])
      callbacks.call("before_action :a, :only => [:show]\nbefore_action :b, only: %i[edit show]", "edit").callbacks.should eq(["b"])
      callbacks.call("before_action :a, \"except\" => :show", "show").callbacks.should be_empty
    end

    it "reads an `only:` constant the class assigns, and leaves another class's unread" do
      body = "PUBLIC = %i[index show].freeze\nbefore_action :authenticate!, except: PUBLIC\nskip_before_action :log, only: PUBLIC + [:feed]"
      callbacks.call("before_action :log\n#{body}", "index").callbacks.should be_empty
      callbacks.call("before_action :log\n#{body}", "edit").callbacks.should eq(["log", "authenticate!"])
      callbacks.call("before_action :log\n#{body}", "feed").callbacks.should eq(["authenticate!"])
      files = {
        "/app/controllers/a_controller.rb" => "class AController < Base\n  PUBLIC = %i[index]\nend\nclass BController < Base\n  before_action :authenticate!, except: PUBLIC\n  skip_before_action :log, only: PUBLIC\nend\n",
      }
      chain = build_chain(files, files.keys)
      b = chain.classes.values.find!(&.name.==("BController"))
      # Unreadable: the callback runs for every action, the skip for none.
      chain.resolve(b, "index").callbacks.should eq(["authenticate!"])
    end

    it "reads a callback spread over lines, with comments between" do
      body = <<-RB
        before_action(
          :authenticate!, # who
          only: [
            :edit, # :show
          ],
        )
        RB
      callbacks.call(body, "edit").callbacks.should eq(["authenticate!"])
      callbacks.call(body, "show").callbacks.should be_empty
    end

    it "reads `if:` lambdas as conditional and `skip_before_action ..., raise: false` as a skip" do
      resolved = callbacks.call("before_action :a, if: -> { request.format.json? }\nbefore_action :b, unless: :devise_controller?", "show")
      resolved.callbacks.should eq(["a", "b"])
      resolved.conditional.should eq(Set{"a"})
      callbacks.call("before_action :a\nskip_before_action :a, raise: false", "show").callbacks.should be_empty
      callbacks.call("before_action :a\nskip_before_action :a, raise: false, if: -> { params[:x] }", "show").lifted.keys.should eq(["a"])
    end

    it "reads block callbacks as the one method they run" do
      callbacks.call("before_action { authenticate_user! }", "show").callbacks.should eq(["authenticate_user!"])
      callbacks.call("before_action only: :show do\n  require_admin! || head(:forbidden)\nend", "show").callbacks.should eq(["require_admin!"])
      callbacks.call("before_action only: :show do\n  require_admin! || head(:forbidden)\nend", "edit").callbacks.should be_empty
      callbacks.call("before_action -> { audit; authenticate! }", "show").callbacks.should be_empty
      callbacks.call("before_action { |c| c.authenticate! }", "show").callbacks.should be_empty
    end

    it "reads `send(:before_action, ...)` and the legacy `*_filter` spellings" do
      callbacks.call("send(:before_action, :a, only: :show)\nbefore_filter :b\nprepend_before_filter :c", "show").callbacks.should eq(["a", "b", "c"])
      callbacks.call("before_filter :b\nskip_before_filter :b, only: :show", "show").callbacks.should be_empty
    end

    it "takes no statement from heredocs, strings, comments, `=begin` or `__END__`" do
      body = <<-RB
        DOC = <<~TXT
          end
          before_action :fake_heredoc
        TXT
        NOTE = "
          before_action :fake_string
        "
        # before_action :fake_comment
        =begin
        before_action :fake_block_comment
        =end
        before_action :real
        def show
        end
        RB
      callbacks.call(body, "show").callbacks.should eq(["real"])
      source = "class DataController < Base\n  before_action :real\nend\n__END__\nclass DataController < Base\n  before_action :fake_data\nend\n"
      chain = build_chain({"/app/controllers/data_controller.rb" => source}, ["/app/controllers/data_controller.rb"])
      chain.resolve(chain.controller_in("/app/controllers/data_controller.rb").not_nil!, "show").callbacks.should eq(["real"])
    end

    it "reads no callback a `def` body registers unless a class macro runs it" do
      body = "def setup\n  before_action :inside_def\nend\nclass << self\n  def public_actions(*names)\n    skip_before_action :authenticate!, only: names\n  end\nend\nbefore_action :authenticate!\npublic_actions :index"
      callbacks.call(body, "index").callbacks.should be_empty
      callbacks.call(body, "edit").callbacks.should eq(["authenticate!"])
    end

    it "applies an `included do` block of a concern a parent includes, and its `class_methods` macros" do
      files = {
        "/app/controllers/concerns/authentication.rb" => <<-RB,
          module Authentication
            extend ActiveSupport::Concern

            included do
              before_action :require_authentication
            end

            class_methods do
              def allow_guests(**options)
                skip_before_action :require_authentication, **options
              end
            end
          end
          RB
        "/app/controllers/application_controller.rb" => "class ApplicationController < ActionController::Base\n  include Authentication\nend\n",
        "/app/controllers/pages_controller.rb"       => "class PagesController < ApplicationController\n  allow_guests only: %i[home]\n  private def home_data; end\nend\n",
      }
      chain = build_chain(files, files.keys)
      pages = chain.controller_in("/app/controllers/pages_controller.rb").not_nil!
      chain.resolve(pages, "home").callbacks.should be_empty
      chain.resolve(pages, "about").callbacks.should eq(["require_authentication"])
      chain.defs.has_key?("home_data").should be_true
    end

    it "expands `except: [*class_method]` and lists another file defines" do
      files = {
        "/lib/discourse.rb"                   => "module Discourse\n  def self.filters\n    @filters ||= %i[latest hot]\n  end\nend\n",
        "/app/controllers/list_controller.rb" => <<-'RB',
          class ListController < ApplicationController
            def self.public_methods_list
              %i[about]
            end
            before_action :ensure_logged_in, except: [*public_methods_list, Discourse.filters.map { |f| :"#{f}_feed" }].flatten
          end
          RB
      }
      chain = build_chain(files, ["/app/controllers/list_controller.rb"])
      list = chain.controller_in("/app/controllers/list_controller.rb").not_nil!
      %w[about latest_feed hot_feed].each { |action| chain.resolve(list, action).callbacks.should be_empty }
      chain.resolve(list, "latest").callbacks.should eq(["ensure_logged_in"])
    end

    it "resolves `only: class_method` by the class's own `def self.x`, never another class's" do
      files = {
        "/app/controllers/posts_controller.rb" => <<-RB,
          class Base2 < ApplicationController
            def self.public_actions
              %i[index show edit]
            end
          end
          class PostsController < ApplicationController
            before_action :authenticate!
            skip_before_action :authenticate!, only: public_actions
            def self.public_actions = [:show]
          end
          class OtherController < ApplicationController
            before_action :authenticate!
            skip_before_action :authenticate!, only: public_actions
          end
          RB
      }
      chain = build_chain(files, files.keys)
      posts = chain.classes.values.find!(&.name.==("PostsController"))
      other = chain.classes.values.find!(&.name.==("OtherController"))
      chain.resolve(posts, "show").callbacks.should be_empty
      chain.resolve(posts, "index").callbacks.should eq(["authenticate!"])
      # Unreadable: the skip applies to no action.
      chain.resolve(other, "show").callbacks.should eq(["authenticate!"])
    end

    it "reads a constant assigned twice or under a condition as unreadable" do
      ["PUBLIC = %i[show]\nPUBLIC = %i[index show] if Rails.env.test?", "if ENV[\"X\"]\n  PUBLIC = %i[index]\nend"].each do |assign|
        resolved = callbacks.call("before_action :authenticate!\n#{assign}\nskip_before_action :authenticate!, only: PUBLIC", "index")
        resolved.callbacks.should eq(["authenticate!"])
      end
    end

    it "adds `with_options` options to the statements in its block" do
      body = "before_action :authenticate!\nwith_options only: [:show] do |c|\n  c.skip_before_action :authenticate!\nend\nwith_options except: :index do\n  before_action :audit\nend"
      callbacks.call(body, "show").callbacks.should eq(["audit"])
      callbacks.call(body, "index").callbacks.should eq(["authenticate!"])
      callbacks.call(body, "edit").callbacks.should eq(["authenticate!", "audit"])
    end

    it "lifts rather than removes a callback a skip or a macro call skips on a condition" do
      callbacks.call("before_action :a\nskip_before_action :a, only: [:show] if Rails.env.test?", "show").lifted.keys.should eq(["a"])
      callbacks.call("before_action :require_authentication\nallow_unauthenticated_access if: :preview?", "show").lifted.keys.should eq(["require_authentication"])
      # A `before_action` under a modifier is read as it always was: unconditional.
      callbacks.call("before_action :a if Rails.env.production?", "show").conditional.should be_empty
      files = {
        "/app/controllers/concerns/public_pages.rb" => "module PublicPages\n  extend ActiveSupport::Concern\n  class_methods do\n    def public_pages(opts = {})\n      skip_before_action :authenticate!, opts\n    end\n  end\nend\n",
        "/app/controllers/posts_controller.rb"      => "class PostsController < ActionController::Base\n  include PublicPages\n  before_action :authenticate!\n  public_pages only: [:show] if Rails.env.development?\nend\n",
      }
      chain = build_chain(files, files.keys)
      resolved = chain.resolve(chain.controller_in("/app/controllers/posts_controller.rb").not_nil!, "show")
      resolved.callbacks.should eq(["authenticate!"])
      resolved.lifted["authenticate!"].should contain("Rails.env.development?")
    end

    it "falls back to the line reader for a class tree-sitter puts in an ERROR node" do
      source = "class ApplicationController < ActionController::Base\n  before_action :authenticate_user!\n\n  def foo\n    x = [1, 2\n  end\nend\n"
      chain = build_chain({"/app/controllers/application_controller.rb" => source}, ["/app/controllers/application_controller.rb"])
      app = chain.controller_in("/app/controllers/application_controller.rb").should_not be_nil
      chain.resolve(app, "index").callbacks.should eq(["authenticate_user!"])
    end
  end
end
