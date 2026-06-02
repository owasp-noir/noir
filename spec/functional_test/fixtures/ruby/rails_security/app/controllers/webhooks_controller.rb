class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  rate_limit to: 10, within: 1.minute, only: :create

  def create
    payload = JSON.parse(request.body.read)
    render json: { ok: true }
  end

  def index
    render json: { up: true }
  end
end
