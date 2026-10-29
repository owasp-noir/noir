class Admin::BackupsController < ApplicationController
  before_action :ensure_admin

  def destroy
    Backup.find(params[:id]).remove
  end
end
