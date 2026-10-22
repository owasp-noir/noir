-- Application-table routes whose value is keyed by the verbs the path
-- implements. Lapis dispatches such a table through `respond_to`, which
-- answers 405 for every verb the table does not name, so the keys are the
-- method set -- not a starting point for an all-verbs fan-out.
local kong = kong

local endpoints = {
  disable = {
    before = function() return kong.response.exit(404) end,
  },
}

local function shared_handler(self)
  return kong.response.exit(200, { message = "shared" })
end

return {
  -- Exactly one declared verb.
  ["/cache"] = {
    DELETE = function()
      kong.cache:purge()
      return kong.response.exit(204)
    end,
  },

  -- Two verbs, with handler bodies that declare their own locals at the
  -- same brace depth as the verb keys (Lua function bodies are not
  -- brace-delimited) and nest tables that are not method keys.
  ["/cache/:key"] = {
    GET = function(self)
      local ttl, err, value = kong.cache:probe(self.params.key)
      if err then
        return kong.response.exit(500, { message = "probe failed" })
      end
      return kong.response.exit(200, { ttl = ttl, value = value })
    end,

    DELETE = function(self)
      kong.cache:invalidate_local(self.params.key)
      return kong.response.exit(204)
    end,
  },

  -- One handler shared by several verbs.
  ["/shared"] = {
    GET = shared_handler,
    HEAD = shared_handler,
  },

  -- Bracketed string keys are the same declaration in different syntax.
  ["/bracket-keys"] = {
    ["GET"] = function() return kong.response.exit(200) end,
    ["OPTIONS"] = function() return kong.response.exit(204) end,
  },

  -- A shared table reached through a module reference names no verb, so
  -- the route keeps the all-methods fallback.
  ["/disabled"] = endpoints.disable,
}
