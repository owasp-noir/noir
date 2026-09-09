-- Value shapes that carry no method evidence, and the one wrapper form
-- that does.
local lapis = require("lapis")
local respond_to = require("lapis.application").respond_to

-- A URL-keyed lookup table is not a route table: a boolean can never be
-- a Lapis handler, so `/fallback/lookup` is not an endpoint at all.
local ACCEPTS_YAML = {
  ["/fallback/lookup"] = true,
}

return lapis.Application:extend({
  -- Filter-only table: says nothing about which methods are served.
  ["/fallback/filtered"] = {
    before = function(self) return ACCEPTS_YAML[self.req.parsed_url.path] end,
  },

  -- A bare function and a named string handler both answer any method.
  ["/fallback/inline"] = function(self) return "inline" end,
  ["/fallback/named"] = "named_handler",

  named_handler = function(self) return "named" end,

  -- The explicit Lapis wrapper limits the route to the verbs it names.
  ["/wrapped"] = respond_to({
    GET = function(self) return "get" end,
    POST = function(self) return "post" end,
  }),
})
