-- `local arg = ngx.arg` shadows the argv global with the body-filter
-- chunk/eof pair, so `arg[1]` / `arg[2]` below are not command-line input.
local arg = ngx.arg

local _M = {}

function _M.body_filter()
  local chunk = arg[1]
  if not arg[2] and os.getenv("ALIAS_MODE") then
    arg[1] = chunk .. "!"
  end
end

return _M
