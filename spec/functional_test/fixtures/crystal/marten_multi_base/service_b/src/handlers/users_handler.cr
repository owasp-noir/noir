class UsersHandler < Marten::Handler
  def get
    ServiceB.list
    respond "B"
  end
end
