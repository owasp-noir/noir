module Api::Auth::RequireAuthToken
  macro included
    before require_auth_token
  end

  private def require_auth_token
    if current_user?
      continue
    else
      json auth_error_json, 401
    end
  end

  private def auth_error_json
    ErrorSerializer.new(
      message: "Not authenticated.",
      details: auth_error_details
    )
  end

  private def auth_error_details : String
    if auth_token
      "The provided authentication token was incorrect."
    else
      "An authentication token is required. Please include a token in an 'auth_token' param or 'Authorization' header."
    end
  end

  # Tells the compiler that the current_user is not nil since we have checked
  # that the user is signed in
  private def current_user : User
    current_user?.as(User)
  end
end
