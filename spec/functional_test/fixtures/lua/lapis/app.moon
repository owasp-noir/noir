lapis = require "lapis"

class extends lapis.Application
  "/moon": =>
    "moon home"
  [show: "/moon/users/:id"]: =>
    @params.id
