-- Real cliargs CLI parsing, with no set_name call on the actual cliargs
-- instance, so the binary name must fall back to the file stem ("app").
local cli = require("cliargs")
cli:add_argument("INPUT", "path to input file")
cli:add_option("-o, --output=DEST", "path to output file", "out.txt")

-- Unrelated object with a same-named set_name method. Its receiver ("logger")
-- was never bound to require("cliargs"), so this must NOT influence the
-- binary name of the cli:// endpoint below.
local logger = {}
function logger:set_name(n) self.name = n end
logger:set_name("audit-logger")

-- Unrelated object with same-named add_option/add_flag methods (e.g. a menu
-- or settings-panel builder). Its receiver ("menu") was never bound to
-- require("cliargs"), so these must NOT be merged into the cli:// params.
local menu = {}
function menu:add_option(name, desc) end
function menu:add_flag(name, desc) end
menu:add_option("theme", "ui theme")
menu:add_flag("dark_mode", "enable dark mode")

local args, err = cli:parse()
print(args, err)
