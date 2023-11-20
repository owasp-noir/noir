module Api::Auth::SkipRequireAuthToken
  macro included
    skip require_auth_token
  end

  # Since sign in is not required, current_user might be nil
  def current_user : User?
    current_user?
  end
end
