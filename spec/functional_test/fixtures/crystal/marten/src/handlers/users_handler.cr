class UsersHandler < Marten::Handler
  def get
    # Access query parameters for filtering
    _filter = request.query_params["filter"]?
    _limit = request.query_params["limit"]?

    respond "Users list"
  end

  def post
    # Access form data
    _username = request.data["username"]?
    _email = request.data["email"]?
    _password = request.data["password"]?

    # Access JSON data
    _json_data = request.json

    respond "User created"
  end
end
