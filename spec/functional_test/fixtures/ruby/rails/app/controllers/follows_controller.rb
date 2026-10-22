class FollowsController < ApplicationController
  def create
    @user = User.find_by_username!(params[:profile_username])
    render 'profiles/show'
  end

  def destroy
    @user = User.find_by_username!(params[:profile_username])
    render 'profiles/show'
  end
end
