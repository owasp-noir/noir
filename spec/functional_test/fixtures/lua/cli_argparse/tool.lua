local argparse = require("argparse")

local parser = argparse("tool", "My tool")
parser:flag("-v --verbose", "Verbose")
parser:option("-p --port", "Port")

local serve = parser:command("serve", "Start server")
serve:option("--host", "Host")
serve:argument("config", "Config file")

local token = os.getenv("API_TOKEN")
local first = arg[1]
print(token, first)
