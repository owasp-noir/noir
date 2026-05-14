local lapis = require("lapis")

return lapis.Application:extend({
  ["/admin/dashboard"] = "dashboard",

  dashboard = function(self)
    local stats = AdminService:stats()
    return render_admin(stats)
  end,

  ["/admin/users/:id"] = function(self)
    local user = AdminUsers.find(self.params.id)
    return json_response(user)
  end,
})
