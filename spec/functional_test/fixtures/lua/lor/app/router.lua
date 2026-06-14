local authRouter = require("app.routes.auth")
local todoRouter = require("app.routes.todo")

return function(app)
    app:use("/auth", authRouter())
    app:use("/todo", todoRouter())
end
