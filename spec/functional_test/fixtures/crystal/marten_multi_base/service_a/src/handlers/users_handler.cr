class UsersHandler < Marten::Handler
  def get
    ServiceA.list
    respond "A"
  end
end
