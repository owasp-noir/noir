-- Production Lapis projects rarely name their application `app` —
-- multi-app monoliths typically use `users_app`, `admin_app`, etc.
-- The analyzer must follow the assignment to surface those routes.
local lapis = require("lapis")

local users_app = lapis.Application()

users_app:get("/api/users", function(self) return "list" end)
users_app:post("/api/users", function(self) return "create" end)
users_app:get("/api/users/:id", function(self) return "show" end)

return users_app
