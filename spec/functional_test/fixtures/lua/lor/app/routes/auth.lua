local lor = require("lor.index")
local authRouter = lor:Router()

authRouter:get("/login", function(req, res, next)
    res:render("login")
end)

authRouter:post("/login", function(req, res, next)
    local username = req.body.username
    req.session.user = username
    res:redirect("/")
end)

authRouter:get("/logout", function(req, res, next)
    req.session.destroy()
    res:redirect("/")
end)

return authRouter
