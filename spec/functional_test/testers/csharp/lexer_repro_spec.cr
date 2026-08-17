require "../../func_spec.cr"

# C# structural-lexer regression test.
#
# The shared line-based scanners in `csharp/common.cr` used to count `{`/`}`
# and `(`/`)` over raw lines with no string masking, so:
#   * a `}` inside a string literal truncated the method block, dropping every
#     callee below it (here SecretHelperCall / AuditLog.Write / Ok /
#     SerializeOrder were lost, only LoadTemplate survived), and
#   * a `(` inside a string default value made the signature run away, dropping
#     both parameters and the body's callees.
# Routed through `Noir::CSharpLexer#masked_lines`, the counters now run over
# code only and recover all of them.
dirty = Endpoint.new("/api/Repro/dirty/{id}", "GET", [
  Param.new("id", "", "path"),
])
dirty.push_callee(Callee.new("LoadTemplate", line: 14))
dirty.push_callee(Callee.new("SecretHelperCall", line: 15))
dirty.push_callee(Callee.new("AuditLog.Write", line: 16))
dirty.push_callee(Callee.new("Ok", line: 17))
dirty.push_callee(Callee.new("SerializeOrder", line: 17))

calc = Endpoint.new("/api/Repro/calc", "GET", [
  Param.new("expr", "", "query"),
  Param.new("limit", "", "query"),
])
calc.push_callee(Callee.new("Ok", line: 27))
calc.push_callee(Callee.new("Compute", line: 27))

interp_get = Endpoint.new("/api/Repro/interp/{id}", "GET", [
  Param.new("id", "", "path"),
])
interp_get.push_callee(Callee.new("SecretHelperCall", line: 35))
interp_get.push_callee(Callee.new("AuditLog.Write", line: 36))
interp_get.push_callee(Callee.new("Ok", line: 37))
interp_get.push_callee(Callee.new("SerializeOrder", line: 37))

interp_post = Endpoint.new("/api/Repro/interp", "POST", [
  Param.new("name", "", "json"),
])
interp_post.push_callee(Callee.new("orderService.Create", line: 43))
interp_post.push_callee(Callee.new("Created", line: 44))
interp_post.push_callee(Callee.new("SerializeOrder", line: 44))

FunctionalTester.new("fixtures/csharp/lexer_repro/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  dirty,
  calc,
  interp_get,
  interp_post,
], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
