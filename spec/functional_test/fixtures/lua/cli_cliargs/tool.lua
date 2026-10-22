local cli = require("cliargs")

cli:set_name("mytool")
cli:add_argument("INPUT", "path to input file")
cli:add_option("-o, --output=DEST", "path to output file", "out.txt")
cli:add_flag("-v, --verbose", "enable verbose output")

local token = os.getenv("API_TOKEN")

local args, err = cli:parse()
print(token, args, err)
