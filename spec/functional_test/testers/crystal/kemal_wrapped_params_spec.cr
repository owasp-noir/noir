require "../../func_spec.cr"

# Regression test: an accessor read wrapped over lines
# (`env.params.query[` / `"q2"` / `]`) was missed by the per-line scan.
FunctionalTester.new("fixtures/crystal/kemal_wrapped_params/", {
  :techs     => 1,
  :endpoints => 2,
}, [
  Endpoint.new("/one", "GET", [
    Param.new("q1", "", "query"),
    Param.new("X-H1", "", "header"),
  ]),
  Endpoint.new("/split", "POST", [
    Param.new("q2", "", "query"),
    Param.new("f2", "", "form"),
    Param.new("X-H2", "", "header"),
    Param.new("j2", "", "json"),
    Param.new("c2", "", "cookie"),
  ]),
]).perform_tests
