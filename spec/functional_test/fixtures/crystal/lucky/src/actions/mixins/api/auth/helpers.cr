module Api::Auth::Helpers
  # The 'memoize' macro makes sure only one query is issued to find the user
  memoize def current_user? : User?
    auth_token.try do |value|
      user_from_auth_token(value)
    end
  end

  private def auth_token : String?
    bearer_token || token_param
  end

  private def bearer_token : String?
    context.request.headers["Authorization"]?
      .try(&.gsub("Bearer", ""))
      .try(&.strip)
  end

  private def token_param : String?
    params.get?(:auth_token)
  end

  private def user_from_auth_token(token : String) : User?
    UserToken.decode_user_id(token).try do |user_id|
      UserQuery.new.id(user_id).first?
    end
  end
end
