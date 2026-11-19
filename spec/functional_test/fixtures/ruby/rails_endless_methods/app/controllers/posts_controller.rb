class PostsController < ApplicationController
  def index = render(json: Post.search(params[:q]))

  def show
    render json: Post.find(params[:id])
  end

  def create
    render json: Post.create!(post_params)
  end

  def update
    render json: Post.find(params[:id]).update!(params.require(:post).permit(allowed))
  end

  private

  def post_params = params.require(:post).permit(:title, :body)

  def allowed = %i[summary tags]
end
