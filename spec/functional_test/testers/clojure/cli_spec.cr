require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

endpoints = [
  build.call("cli://tool", [
    Param.new("port", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]
FunctionalTester.new("fixtures/clojure/cli_tools/", {:techs => 1, :endpoints => endpoints.size}, endpoints).perform_tests

babashka_endpoints = [
  build.call("cli://taskrunner/run", [
    Param.new("port", "", "flag"),
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://taskrunner/build", [
    Param.new("tag", "", "flag"),
  ]),
]
FunctionalTester.new("fixtures/clojure/cli_babashka/", {:techs => 1, :endpoints => babashka_endpoints.size}, babashka_endpoints).perform_tests

# Regression for babashka.cli dispatch-table attribution/extraction bugs:
#   - `:spec` deliberately precedes its own `:cmds` sibling (map literals are
#     unordered) — options must still land on the entry that structurally
#     encloses them, never a sticky "last :cmds seen" cursor.
#   - `:cmds ["docker" "start"]` is a two-segment subcommand and must not
#     collapse to `cli://tool/docker` (losing "start" vs "stop").
#   - `:verbose {:desc "..."}` has no `:coerce` key and must still surface.
#   - the unrelated `log-opts` map (`{:level {:coerce :keyword}}`), declared
#     after the last dispatch entry and outside any `:spec` map, must never
#     be attributed to any endpoint.
babashka_scoping_endpoints = [
  build.call("cli://tool/docker/start", [
    Param.new("detach", "", "flag"),
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://tool/docker/stop", [
    Param.new("force", "", "flag"),
  ]),
]
FunctionalTester.new("fixtures/clojure/cli_babashka_scoping/", {:techs => 1, :endpoints => babashka_scoping_endpoints.size}, babashka_scoping_endpoints).perform_tests

# environ.core only ever annotates params on a `cli://` endpoint another,
# CLI-specific marker (here clojure.tools.cli) already established — it must
# never gate CLI detection on its own (see cli_environ_fp below).
environ_endpoints = [
  build.call("cli://reporter", [
    Param.new("verbose", "", "flag"),
    Param.new("DATABASE_URL", "", "env"),
    Param.new("API_KEY", "", "env"),
  ]),
]
FunctionalTester.new("fixtures/clojure/cli_environ/", {:techs => 1, :endpoints => environ_endpoints.size}, environ_endpoints).perform_tests

# Regression: a bare `environ.core` require is a generic 12-factor
# config-reading pattern used by web apps/workers just as much as CLIs (same
# category as bare System/getenv). `config.clj` here has no CLI-specific
# marker at all — only `handler.clj` (a different file) pulls in Ring — so
# this must detect 0 clojure_cli techs and emit 0 cli:// endpoints, even
# though `handler.clj` still gets picked up as a Ring app.
FunctionalTester.new("fixtures/clojure/cli_environ_fp/", {
  :techs     => 1,
  :endpoints => 0,
}, [] of Endpoint).perform_tests

# Regression: `environ.core` required under an alias (`:as environ`, not
# `:refer [env]`) must not make a bare `(env ...)` call — here just an
# ordinary local fn param shadowing the name "env" — look like an environ
# lookup. Only the "timeout" flag from clojure.tools.cli should surface;
# neither a bogus TIMEOUT nor DATABASE_URL env param should appear.
environ_alias_endpoints = [
  build.call("cli://toolkit", [
    Param.new("timeout", "", "flag"),
  ]),
]
FunctionalTester.new("fixtures/clojure/cli_environ_alias_fp/", {:techs => 1, :endpoints => environ_alias_endpoints.size}, environ_alias_endpoints).perform_tests
