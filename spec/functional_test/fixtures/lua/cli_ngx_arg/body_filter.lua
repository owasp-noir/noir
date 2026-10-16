-- OpenResty body_filter_by_lua: ngx.arg[1] is the chunk and ngx.arg[2] the
-- eof flag, not command-line arguments.
local _M = {}

function _M.body_filter(ctx)
  local chunk, eof = ngx.arg[1], ngx.arg[2]
  if ctx.arg[1] == nil and os.getenv("FILTER_MODE") then
    ngx.arg[1] = "rewritten"
  end
  return chunk, eof
end

return _M
