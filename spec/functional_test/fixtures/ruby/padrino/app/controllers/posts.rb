# Regression guard: route DSL inside an RDoc-style comment is
# documentation, not a registration.
#
#     get :should_not_appear do
#       'nope'
#     end

PadrinoTest.controllers :posts do
  get :index do
    # url_for(:posts, :index) => "/posts"
    params[:page]
  end

  get :show, with: :id do
    # url_for(:posts, :show, id: 5) => "/posts/show/5"
    params[:id]
  end

  get :archive, map: '/posts/archive/:year' do
    # url_for(:posts, :archive, year: 2024) => "/posts/archive/2024"
    params[:year]
  end

  post :create do
    # url_for(:posts, :create) => "/posts/create"
    request.env["HTTP_X_REQUEST_ID"]
  end

  get "/latest" do
    # A literal-path route nested inside a controller block is still
    # grouped under the controller's own prefix, same as `namespace`.
    params[:limit]
  end
end

# `parent:` prepends the parent resource's own segment + `:<parent>_id`
# ahead of the controller's name segment.
PadrinoTest.controllers :comments, parent: :post do
  get :index do
    # url_for(:comments, :index, post_id: 5) => "/post/5/comments"
    params[:sort]
  end
end
