class HomeHandler < Marten::Handler
  def get
    # Access query parameters
    _name = request.query_params["name"]?
    # Access headers
    _auth_token = request.headers["Authorization"]?
    # Access cookies
    _session_id = request.cookies["session_id"]?

    respond "Hello World!"
  end
end
