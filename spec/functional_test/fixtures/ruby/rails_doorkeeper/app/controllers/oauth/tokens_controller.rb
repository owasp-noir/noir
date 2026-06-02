module Oauth
  class TokensController < Doorkeeper::TokensController
    def create
      AuditLog.write("oauth token issued")
      grant = params[:grant_type]
      super
    end

    def revoke
      TokenRevoker.revoke(params[:token])
    end
  end
end
