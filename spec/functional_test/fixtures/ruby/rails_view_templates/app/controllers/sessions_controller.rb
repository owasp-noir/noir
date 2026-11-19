class SessionsController < ApplicationController
  def create
    User.authenticate(params[:email], params[:password])
  end
end
