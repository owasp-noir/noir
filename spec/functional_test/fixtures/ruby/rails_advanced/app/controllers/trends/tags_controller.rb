class Trends::TagsController < ApplicationController
  def index
  end

  def show
  end

  def approve
    @tag = Tag.find(params[:id])
  end

  def batch
  end

  def merged?
    render json: { merged: request.headers["X-Merge-Token"].present? }
  end
end
