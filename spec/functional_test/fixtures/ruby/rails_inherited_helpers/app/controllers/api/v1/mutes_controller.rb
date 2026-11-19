class Api::V1::MutesController < Api::BaseController
  def index
    # inherited helper called straight from the action
    render json: Mute.limit(limit_param(DEFAULT_ACCOUNTS_LIMIT))
  end
end
