Admin.controllers :users do
  get :index do
    # Mounted under /admin -> url_for(:users, :index) => "/admin/users"
    params[:page]
  end

  get :show, map: '/users/:id/profile' do
    # `map:` is relative to the mount prefix, not the controller name.
    params[:id]
  end
end
