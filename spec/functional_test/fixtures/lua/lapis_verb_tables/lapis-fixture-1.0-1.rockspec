package = "lapis-verb-tables-fixture"
version = "1.0-1"
source = { url = "git+https://example.com/lapis-verb-tables-fixture.git" }
description = { summary = "Lapis application tables keyed by HTTP verb" }
dependencies = {
  "lua >= 5.1",
  "lapis",
}
build = { type = "builtin" }
