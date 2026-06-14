local lor = require("lor.index")
local router = require("app.router")

local app = lor()

-- direct route on the application object
app:get("/", function(req, res, next)
    res:send("home")
end)

-- in-file router mount: apiRouter is a local lor:Router() mounted under /api
local apiRouter = lor:Router()
apiRouter:get("/ping", function(req, res, next)
    res:send("pong")
end)
app:use("/api", apiRouter())

-- cross-file business routers
router(app)

app:run()
