package = "lapis-fixture"
version = "1.0-1"
source = { url = "git+https://example.com/lapis-fixture.git" }
description = { summary = "Lapis fixture" }
dependencies = {
  "lua >= 5.1",
  "lapis",
}
build = { type = "builtin" }
