class Api::SignUps::Create < ApiAction
  include Api::Auth::SkipRequireAuthToken

  post "/api/sign_ups" do
    user = SignUpUser.create!(params)
    cookies.get("name1")
    cookies["name2"]
    cookies.get_raw("name3")

    json({token: UserToken.generate(user)})
  end
end
