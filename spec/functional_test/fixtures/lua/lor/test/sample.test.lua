-- lor's own test convention (`*.test.lua` under a `test/` dir). The routes
-- below are phantom test-app routes and MUST NOT be emitted as endpoints.
local lor = require("lor.index")
local app = lor()

app:get("/phantom/test/route", function(req, res, next)
    res:send("should not be detected")
end)

app:post("/user/123/create", function(req, res, next)
    res:send("should not be detected")
end)

app:run()
