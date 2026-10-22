-- A plain script: the bare global `arg` is argv, also after `..` concatenation.
local name = arg[1]
print("hello " .. name .. "|"..arg[2])
