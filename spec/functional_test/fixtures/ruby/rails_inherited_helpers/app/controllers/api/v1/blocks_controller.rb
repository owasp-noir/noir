class Api::V1::BlocksController < Api::BaseController
  def index
    @accounts = paginated_blocks
    render json: @accounts
  end

  private

  # same-file helper that calls the inherited one (mastodon's exact shape)
  def paginated_blocks
    Block.paginate_by_max_id(limit_param(DEFAULT_ACCOUNTS_LIMIT), params[:max_id], params[:since_id])
  end
end
