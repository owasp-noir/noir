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

return app
