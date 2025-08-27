class UserDetailHandler < Marten::Handler
  def get
    # Access path parameters
    user_id = params["id"]
    
    # Access query parameters
    include_profile = request.query_params["include_profile"]?
    
    respond "User #{user_id}"
  end

  def put
    # Access path parameters
    user_id = params["id"]
    
    # Access form data
    name = request.data["name"]?
    email = request.data["email"]?
    
    respond "User #{user_id} updated"
  end

  def delete
    user_id = params["id"]
    respond "User #{user_id} deleted"
  end
end