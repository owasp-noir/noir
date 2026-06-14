local lor = require("lor.index")
local tinsert = table.insert
local todoRouter = lor:Router()

-- a model object with verb-named methods MUST NOT be mistaken for routes
local todo_model = require("app.model.todo")

todoRouter:post("/complete", function(req, res, next)
    todo_model:get(req.body.id)
    res:json({ ok = true })
end)

todoRouter:put("/add", function(req, res, next)
    local list = {}
    tinsert(list, req.body.item)
    res:json({ ok = true })
end)

todoRouter:delete("/delete", function(req, res, next)
    todo_model:delete(req.body.id)
    res:json({ ok = true })
end)

todoRouter:get("/find/:filter", function(req, res, next)
    res:json({})
end)

-- relative path without a leading slash (served under the /todo mount)
todoRouter:post("index", function(req, res, next)
    res:json({})
end)

-- :all matches every HTTP method
todoRouter:all("/status", function(req, res, next)
    res:json({})
end)

return todoRouter
