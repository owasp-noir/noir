class UsersHandler < Marten::Handler
  def get
    records = UserSearch.list
    UserPresenter.render(records)
    respond "Users"
  end

  def post
    UserCreator.create
    respond "Created"
  end
end
