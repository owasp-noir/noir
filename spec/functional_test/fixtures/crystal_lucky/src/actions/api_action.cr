# Include modules and add methods that are for all API requests
abstract class ApiAction < Lucky::Action
  # APIs typically do not need to send cookie/session data.
  # Remove this line if you want to send cookies in the response header.
  disable_cookies
  accepted_formats [:json]

  include Api::Auth::Helpers

  # By default all actions require sign in.
  # Add 'include Api::Auth::SkipRequireAuthToken' to your actions to allow all requests.
  include Api::Auth::RequireAuthToken

  # By default all actions are required to use underscores to separate words.
  # Add 'include Lucky::SkipRouteStyleCheck' to your actions if you wish to ignore this check for specific routes.
  include Lucky::EnforceUnderscoredRoute
end
