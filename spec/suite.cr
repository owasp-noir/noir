# The whole test suite as one program, built once and re-run as a binary.
#
# Compiling `src/` is essentially the entire cost of running specs, and it does
# not grow when the suites are combined: measured locally on a warm compiler
# cache, `crystal spec spec/unit_test` takes 28.7s (9.1s of it running examples,
# the rest compiling) and `crystal spec spec/functional_test` another 23.5s,
# while compiling both together costs the same 20.9s as unit alone. CI was
# paying that compile four times over, once for each of unit, functional, unit
# randomized and functional randomized.
#
# Built as a binary instead, one 20s compile produces something that runs all
# 30,357 examples in 18s using 0.3GB of RSS, so a second run in randomized
# order, or a filtered re-run while debugging, is free of the compiler
# entirely. Two runs in parallel finish in 19s wall against 36s sequential.
#
# The file is deliberately not named `*_spec.cr`: `crystal spec` with no
# arguments globs those, and picking this up as well would compile every
# example twice into the same program.
#
# One thing the binary does not inherit from `crystal spec` is positional path
# arguments (`bin/noir_spec spec/unit_test` fails with `unknown argument`).
# Narrow a run with `-e SUBSTRING`, `--location file:line` or `--tag`.
# `FunctionalTester` also resolves its fixtures through relative paths, so run
# the binary from the repository root.
require "spec"
require "./unit_test/**"
require "./functional_test/testers/**"
