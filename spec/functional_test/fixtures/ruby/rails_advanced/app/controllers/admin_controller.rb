class AdminController < ApplicationController
  def dashboard
    @page = params[:page]
  end

  def rebuild
    @target = params[:target]
  end
end
