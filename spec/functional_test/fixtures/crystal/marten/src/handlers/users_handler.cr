class UsersHandler < Marten::Handler
  def get
    # Access query parameters for filtering
    filter = request.query_params["filter"]?
    limit = request.query_params["limit"]?
    
    respond "Users list"
  end

  def post
    # Access form data
    username = request.data["username"]?
    email = request.data["email"]?
    password = request.data["password"]?
    
    # Access JSON data
    json_data = request.json
    
    respond "User created"
  end
end