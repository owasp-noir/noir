-- Sub-application mounted under a path prefix. Lapis prepends
-- `app.path` to every route once the app is `include`d by a parent,
-- so each pattern below resolves relative to `/api/users`.
local lapis = require("lapis")
local respond_to = require("lapis.application").respond_to
local app = lapis.Application()
app.name = "api.users."
app.path = "/api/users"

-- Empty pattern resolves to the bare prefix: `/api/users`.
app:match("users", "", function(self) return "list" end)

-- Lua-pattern constraint on the param is stripped: `/api/users/:id`.
app:match("user", "/:id[%d]", function(self) return "show" end)

-- Optional group peels to the required base: `/api/users/:id/posts`.
app:match("posts", "/:id[%d]/posts(/page/:page[%d])", function(self) return "posts" end)

-- Inline respond_to limits the verbs to GET and PUT (no phantom
-- POST/DELETE/PATCH), and `before` is not a verb.
app:match("settings", "/:id[%d]/settings", respond_to({
  before = function(self) end,
  GET = function(self) return "get" end,
  PUT = function(self) return "put" end,
}))

return app
