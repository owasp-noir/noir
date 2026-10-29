class DraftsController < ApplicationController
  requires_login

  def destroy
    Draft.find(params[:id]).destroy!
  end
end
