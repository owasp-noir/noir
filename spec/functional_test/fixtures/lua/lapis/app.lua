local lapis = require("lapis")
local app = lapis.Application()

-- Method-specific calls
app:get("/", function(self) return "home" end)
app:get("/users", function(self) return "list" end)
app:post("/login", function(self) return "login" end)
app:put("/profile", function(self) return "profile" end)
app:delete("/items/:id", function(self) return "delete" end)
app:patch("/notes/:id", function(self) return "patch" end)

-- Generic match (any HTTP method).
app:match("/about", function(self) return "about" end)

-- Named match — second string arg is the URL pattern.
app:match("user_show", "/users/:id", function(self) return self.params.id end)

-- Splat parameter.
app:get("/files/*splat", function(self) return self.params.splat end)

-- Lapis README opens with the named-route verb form
-- `app:get(name, "/path", handler)`. The first arg is the route name,
-- not the URL — the analyzer must reach the second string.
app:get("index", "/named", function(self) return "named" end)
app:post("create_user", "/named/users", function(self) return "create" end)

-- Code generator templates ship MoonScript snippets inside
-- Lua long-bracket strings. Patterns *inside* the here-string are
-- template source, never live routes.
local template = [[
class extends lapis.Application
  "/from-template": =>
    "should not appear"
  app:get("/also-template", function() end)
]]

return app
