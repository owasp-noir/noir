class UserDetailHandler < Marten::Handler
  def get
    user_id = params["id"]
    user = UserLookup.find(user_id)
    respond UserPresenter.render(user)
  end
end
