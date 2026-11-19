class PostsController < ApplicationController
  # mastodon: params.slice(:limit, ...).permit(:limit, ...)
  def index
    render json: Post.page(pagination_params)
  end

  # params[:key].permit(...)
  def create
    Post.create!(params[:post].permit(:title, :body))
  end

  # leading-dot chain with `params` on its own line (rubocop multiline style)
  def update
    Post.find(params[:id]).update!(
      params
        .require(:post)
        .permit(:title, :published)
    )
  end

  # JSON:API style double require
  def comment
    Comment.create!(params.require(:data).require(:attributes).permit(:text, :author))
  end

  private

  def pagination_params
    params.slice(:limit, :max_id).permit(:limit, :max_id)
  end
end
