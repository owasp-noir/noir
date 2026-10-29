require "../../spec_helper"
require "../../../src/miniparsers/rails_callback_chain"

private def build_chain(files : Hash(String, String), controllers : Array(String)) : Noir::RailsCallbackChain
  others = files.keys - controllers
  Noir::RailsCallbackChain.build(controllers, others) { |path| files[path]?.try(&.lines) }
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
end
