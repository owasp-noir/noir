class AdminController < ApplicationController
  def dashboard
    @page = params[:page]
  end

  def rebuild
    @target = params[:target]
  end

  def with_dash
    @mode = params[:dash_mode]
  end
end
