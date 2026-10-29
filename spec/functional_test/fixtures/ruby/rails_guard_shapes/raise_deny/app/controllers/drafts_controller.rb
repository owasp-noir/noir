class DraftsController < ApplicationController
  before_action :ensure_logged_in

  def destroy
    Draft.find(params[:id]).destroy!
  end
end
