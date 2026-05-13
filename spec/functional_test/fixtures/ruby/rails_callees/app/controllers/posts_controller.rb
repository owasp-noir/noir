class PostsController < ApplicationController
  def index
    posts = PostQuery.list(params[:page])
    AuditLog.write("index")
    render(json: serialize_posts(posts))
  end

  def show
    post = Post.find(params[:id])
    render(json: serialize_post(post))
  end

  def create
    post = PostCreator.create(post_params)
    AuditLog.write("create")
    render(json: serialize_post(post), status: :created)
  end

  def preview
    preview = PreviewBuilder.build(params[:draft])
    render(json: serialize_preview(preview))
  end

  private

  def post_params
    params.require(:post).permit(:title)
  end
end
