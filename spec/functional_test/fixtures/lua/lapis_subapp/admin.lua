-- A sub-app whose application variable is not the bare `app`, with a
-- mount prefix applied to method-specific route calls.
local lapis = require("lapis")
local admin_app = lapis.Application()
admin_app.path = "/admin"

-- Named verb form: the first string is the route name, the second is
-- the (prefix-relative) path -> `/admin/dashboard`.
admin_app:get("dashboard", "/dashboard", function(self) return "dash" end)

-- Plain verb form with a Lua-pattern constraint -> `/admin/stats/:metric`.
admin_app:get("/stats/:metric[%a]", function(self) return "stats" end)

return admin_app
