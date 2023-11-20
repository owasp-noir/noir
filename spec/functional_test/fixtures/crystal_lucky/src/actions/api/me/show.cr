class Api::Me::Show < ApiAction
  get "/api/me" do
    remote_ip = request.headers["X-Forwarded-For"]
    _ = remote_ip
    params.from_query["q"] # => "Lucky"
    params.get("query")
    params.get(:filter)
    json UserSerializer.new(current_user)
  end
end
