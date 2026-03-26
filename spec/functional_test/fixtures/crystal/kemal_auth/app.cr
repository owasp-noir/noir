require "kemal"

# Route with session user check
get "/profile" do |env|
  user = env.session.string("user_id")
  {user: user}.to_json
end

# Route with basic_auth
get "/api/secret" do |env|
  basic_auth env
  "Secret data"
end

# Unprotected API route (far from any auth patterns)
class HealthController
  def index
    get "/api/health" do |_env|
      {status: "ok"}.to_json
    end
  end
end
