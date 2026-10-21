class Preferences::BaseController < ApplicationController
  def show; end

  def update
    current_user.update(params.require(:user).permit(:locale))
  end
end
