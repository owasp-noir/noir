lapis = require "lapis"

class extends lapis.Application
  -- respond_to block names the verbs it serves.
  [profile: "/profile"]: respond_to {
    GET: => @write "get"
    POST: => @write "post"
  }
  -- A wrapped bare arrow handles any HTTP method.
  [account: "/account/:id"]: capture_errors_json =>
    @write "account"

  -- Bare key whose value is a handler EXPRESSION (not `=>`/`respond_to`)
  -- is still a route. A bare key mapping to a string literal would be a
  -- config entry and is intentionally NOT treated as a route.
  "/console": require("lapis.console").make!
