class UploadsController < ApplicationController
  include ExternalUploadHelpers

  before_action :authenticate_user!

  def create
    Upload.create!(file: params[:file])
  end
end
