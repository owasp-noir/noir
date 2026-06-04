require "../../func_spec.cr"

# Scala structural-lexer regression test.
#
# The Scala analyzers used to strip each line in isolation
# (`scala_code_line(line)` = `strip_non_code_with_state(line, 0, false)`),
# resetting the block-comment depth and multiline-string flag every line. So
# route-shaped Akka DSL inside a `"""…"""` triple-quoted string and inside a
# multi-line `/* … */` comment leaked as phantom endpoints. Threaded through
# `Noir::ScalaLexer` (which carries that state across the whole file), only the
# real `path("real")` route survives.
expected_endpoints = [
  Endpoint.new("/real", "GET"),
]

FunctionalTester.new("fixtures/scala/lexer_repro/", {
  :techs     => 1,
  :endpoints => 1,
}, expected_endpoints).perform_tests
