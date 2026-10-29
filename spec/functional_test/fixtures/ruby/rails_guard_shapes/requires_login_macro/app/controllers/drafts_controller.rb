class DraftsController < ApplicationController
  requires_login except: [:index]

  def index
    Draft.all
  end

  def destroy
    Draft.find(params[:id]).destroy!
  end
end
