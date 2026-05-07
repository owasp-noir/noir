local lapis = require("lapis")

return lapis.Application:extend({
  ["/admin/dashboard"] = "dashboard",
  ["/admin/users"] = function(self) return "admin users" end,
})
