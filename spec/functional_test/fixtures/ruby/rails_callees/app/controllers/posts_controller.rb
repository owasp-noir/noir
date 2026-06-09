class PostsController < ApplicationController
  def index
    posts = PostQuery.list(params[:page])
    AuditLog.write("index")
    render json: serialize_posts(posts)
  end

  def show
    post = Post.find(params[:id])
    render json: serialize_post(post)
  end

  def create
    post = PostCreator.create(post_params)
    AuditLog.write("create")
    render json: serialize_post(post), status: :created
  end

  def preview
    preview = PreviewBuilder.build(params[:draft])
    render json: serialize_preview(preview)
  end

  def implicit_preview
    draft = PreviewBuilder.build(params[:draft])
    AuditLog.write("implicit")
    render json: serialize_preview(draft)
  end

  def implicit_preview_legacy
    draft = PreviewBuilder.build(params[:draft])
    AuditLog.write("legacy")
    render json: serialize_preview(draft)
  end

  def destroy_memory
    MemoryStore.destroy(params[:id])
    AuditLog.write("destroy_memory")
  end

  private

  def post_params
    params.require(:post).permit(:title)
  end
end
