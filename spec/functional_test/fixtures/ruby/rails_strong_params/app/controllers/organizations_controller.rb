class OrganizationsController < ApplicationController
  def show
    @organization = Organization.find(params[:id])
  end

  def users
    @users = Organization.find(params[:organization_id]).users.page(params[:page])
  end
end
