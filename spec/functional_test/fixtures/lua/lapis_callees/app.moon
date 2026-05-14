lapis = require "lapis"

class extends lapis.Application
  "/moon": =>
    moon_service.load @params
    render_moon "home"
  [show: "/moon/users/:id"]: =>
    user = Users\find @params.id
    json_response user
