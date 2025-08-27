class HomeHandler < Marten::Handler
  def get
    # Access query parameters
    name = request.query_params["name"]?
    # Access headers
    auth_token = request.headers["Authorization"]?
    # Access cookies
    session_id = request.cookies["session_id"]?
    
    respond "Hello World!"
  end
end