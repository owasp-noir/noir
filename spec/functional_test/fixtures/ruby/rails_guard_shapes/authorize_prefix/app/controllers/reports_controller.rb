class ReportsController < ApplicationController
  before_action :authorize_admin

  def index
    Report.all
  end

  private

  def authorize_admin
    head :forbidden unless current_user&.admin?
  end
end
