import respond_to from require "lapis.application"

-- MoonScript controllers declare their mount prefix as a class field
-- `@path: "/dashboard"`, the MoonScript analogue of Lua's `app.path`.
-- Every route below resolves under that prefix.
class Dashboard extends lapis.Application
  @path: "/dashboard"
  @name: "dashboard_"

  [overview: "/overview"]: =>
    @write "overview"

  [stats: "/stats/:id[%d]"]: respond_to {
    GET: => @write "get"
    DELETE: => @write "del"
  }
