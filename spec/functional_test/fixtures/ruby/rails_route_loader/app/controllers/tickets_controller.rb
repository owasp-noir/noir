class TicketsController < ApplicationController
  def index
    render json: {}
  end

  def update
    render json: {}
  end

  def merge
    render json: {}
  end

  def search
    render json: { q: params[:query] }
  end

  def stats
    render json: {}
  end
end
