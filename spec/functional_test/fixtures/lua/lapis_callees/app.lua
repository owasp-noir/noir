local lapis = require("lapis")
local app = lapis.Application()

local named_profile = function(self)
  local profile = Profiles.find(self.params.id)
  return render_json(profile)
end

app:get("/users", function(self)
  local users = UserService:list(self.params.page)
  Audit.write("users")
  return render_json(users)
end)

app:post("/users/:id", function(self)
  local user = Users.update(self.params.id)
  return respond({ json = user })
end)

app:match("/health", function(self)
  health_check()
  return respond_ok()
end)

app:get("/named", "named_profile")

-- app:get("/ignored", function(self) Fake.call() end)
app:get("/string-noise", function(self)
  local text = "Fake.call()"
  return clean_text(text)
end)

local identifier_profile = function(self)
  return IdentifierService.show(self.params.id)
end

app:get("/identifier", identifier_profile)

return app
