class Api::SignIns::Create < ApiAction
  include Api::Auth::SkipRequireAuthToken

  post "/api/sign_ins" do
    SignInUser.run(params) do |operation, user|
      params.from_json["users"]
      if user
        json({token: UserToken.generate(user)})
      else
        raise Avram::InvalidOperationError.new(operation)
      end
    end
  end
end
