local argparse = require "argparse"
local parser = argparse("tool")
-- parser:option("--old")
parser:option("--real")
--[[
parser:flag("--block-old")
local d = os.getenv("DOC_ONLY")
]]
local home = os.getenv("READ_ME")
