module ExternalUploadHelpers
  extend ActiveSupport::Concern

  def create_multipart
    Upload.create!(file_name: params[:file_name])
  end
end
