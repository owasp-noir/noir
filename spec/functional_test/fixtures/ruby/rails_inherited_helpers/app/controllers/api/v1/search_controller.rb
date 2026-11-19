class Api::V1::SearchController < Api::BaseController
  include Sortable

  def index
    render json: Search.run(params[:q], sort_options)
  end
end
