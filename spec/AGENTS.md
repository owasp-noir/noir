# AGENTS.md - Guide for Adding Tests

This document explains the test directory structure and how to add new test cases.

## Directory Structure

```
spec/
├── spec_helper.cr              # Shared test helpers
├── suite.cr                    # Entry point: both CI suites in one binary
├── unit_test/                  # Unit tests (included in CI)
├── functional_test/            # Functional/integration tests (included in CI)
│   ├── func_spec.cr            # FunctionalTester class
│   ├── fixtures/               # Sample source code for each language/framework
│   └── testers/                # Test specs that validate endpoint detection
└── uncovered_test/             # Uncovered test cases (NOT included in CI)
    ├── func_spec.cr            # UncoveredFunctionalTester class
    ├── fixtures/               # Sample source code for uncovered cases
    └── testers/                # Test specs for uncovered cases
```

## Directory Roles

### `unit_test/`
Contains unit tests that verify individual components in isolation. Mirrors the `src/` directory structure.

- **Included in CI**: Yes (`just test` / `just test-unit`)
- **Structure**: `spec/unit_test/{component}/{test_file}_spec.cr`
- **Examples**: analyzer, detector, output_builder, tagger, etc.

### `functional_test/`
Contains functional (integration) tests that verify end-to-end endpoint detection and analysis for each supported language/framework.

- **Included in CI**: Yes (`just test` / `just test-func`)
- **Structure**:
  - Fixtures: `spec/functional_test/fixtures/{language}/{framework}/`
  - Testers: `spec/functional_test/testers/{language}/{framework}_spec.cr`

### `uncovered_test/`
A staging area for test cases that are **not yet fully covered** or are **expected to fail**. This directory is separated from CI to avoid blocking builds while still tracking known gaps.

- **Included in CI**: No (run manually with `just test-uncovered`)
- **Structure**:
  - Fixtures: `spec/uncovered_test/fixtures/{language}/{framework}/`
  - Testers: `spec/uncovered_test/testers/{language}/{framework}_spec.cr`

## How to Run Tests

```bash
just spec-build        # Build the whole suite as bin/noir_spec
just test              # spec-build, then run every CI example once
just test-random       # Re-run the built binary in randomized example order
just test-seed 12345   # Re-run it in one specific order
just test-unit         # Run unit tests only (compiles just that directory)
just test-func         # Run functional tests only (compiles just that directory)
just test-uncovered    # Run uncovered tests only (not in CI)
```

`spec/suite.cr` requires `unit_test/**` plus `functional_test/testers/**` and
nothing else, so `bin/noir_spec` holds exactly the 30,356 examples CI runs
(5,697 unit and 24,659 functional). `uncovered_test/` is deliberately outside
it, which is also why `crystal spec` with no arguments is the wrong command
here: its default glob sweeps up `uncovered_test/` too, and those examples are
expected to fail.

Two constraints come with the binary:

- **Run it from the repository root.** `FunctionalTester` resolves fixtures
  through a relative `./spec/functional_test/...` path.
- **It takes no positional paths.** `bin/noir_spec spec/unit_test` fails with
  `unknown argument`. Narrow a run with a filter instead:

```bash
./bin/noir_spec -e hono                                   # ~49 examples
./bin/noir_spec --location spec/unit_test/foo_spec.cr:42   # one example
./bin/noir_spec --dry-run                                  # list without running
```

### Why one binary

Compiling `src/` is essentially the whole cost of a spec run, and it does not
grow when the suites are combined. Measured locally on a warm compiler cache:

| Command | wall | running examples | peak RSS |
|---|---|---|---|
| `crystal spec spec/unit_test` (5,697 ex) | 28.7s | 9.1s | 6.1 GB |
| `crystal spec spec/functional_test` (24,659 ex) | 23.5s | 8.3s | 5.2 GB |
| both suites compiled together | 20.9s | - | 6.1 GB |
| `crystal build spec/suite.cr -o bin/noir_spec` | 20.0s | - | 6.6 GB |
| `./bin/noir_spec` (30,356 ex) | 18.9s | 18.0s | 0.3 GB |

So the compile is paid once and every re-run after that is 18s on 0.3GB. Two
runs of the binary in parallel finish in 19s wall against 36s sequential, which
is what CI does with the default and randomized orders. CI previously compiled
the same program four times (unit, functional, and both again randomized) for
about 90s each.

### While working on one analyzer

Don't run the whole suite on every edit. Target the one tester:

```bash
just test-func-one javascript/hono    # crystal spec spec/functional_test/testers/javascript/hono_spec.cr
just test-func-lang python            # every tester under testers/python/
```

Measured on this repo: one tester **~8.5s**, one language directory ~10.5s.
Compiling one file is still ~10s cheaper than compiling the suite, so these
recipes stay on `crystal spec`. If `bin/noir_spec` is already built and your
change is in a spec rather than in `src/`, `./bin/noir_spec -e hono` beats both.

Two things worth knowing before you try to make that faster:

- **Compiling `src/` is essentially the whole cost.** The single-tester run
  above executes its 78 examples in ~0.06s; the other ~8.5s is the compiler.
  The number of spec files barely matters: 55 python testers compile in about
  the same time as all 576. So narrowing the target below one file, or sharding
  the suite across jobs, buys nothing.
- **`--example` works too, and is cheap.** `FunctionalTester` scans lazily: the
  first example to run triggers its tester's scan, so a filter only pays for the
  testers it selects. `--example hono` costs ~0.2s of run time against ~6.9s
  before the scans moved out of collection time. It still pays the ~8.5s
  compile, so a path and a filter cost about the same with `crystal spec`; use
  whichever names what you want.

### Assertions go inside the example

`FunctionalTester` scans on first use from *inside* an example. So when you
reach past `perform_tests` for a one-off assertion, do the lookup in the `it`
block:

```crystal
it "keeps a single path param" do
  endpoint = tester.endpoints.find { |ep| ep.url == "/users/:id" }   # scans here
  ...
end
```

Not in the `describe` body, which runs at collection time. Crystal installs its
spec runner with `at_exit` and skips it entirely when the process is already
exiting on an error, so anything that raises during collection takes the whole
run down and reports `0 examples` — no failure, no name, nothing to grep. That
is what moving the scan into the examples fixed; putting it back reintroduces
it. `tester.url = ...` is the one pre-scan setter, and it raises if the scan has
already run.

## How to Add a Functional Test

### 1. Add Fixture Code

Create sample source code under `fixtures/` that represents the endpoints to be detected.

```
spec/functional_test/fixtures/{language}/{framework}/
```

For example, to add a Python Django fixture:
```
spec/functional_test/fixtures/python/django/urls.py
spec/functional_test/fixtures/python/django/views.py
```

### 2. Add a Test Spec

Create a test spec under `testers/` that defines expected endpoints and runs the `FunctionalTester`.

```
spec/functional_test/testers/{language}/{framework}_spec.cr
```

Example test spec:
```crystal
require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/users", "GET"),
  Endpoint.new("/users", "POST", [
    Param.new("name", "", "json"),
    Param.new("email", "", "json"),
  ]),
]

FunctionalTester.new("fixtures/{language}/{framework}/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
```

### 3. Run and Verify

```bash
crystal spec spec/functional_test/testers/{language}/{framework}_spec.cr
```

## How to Add an Uncovered Test

Use the same process as functional tests, but place files under `uncovered_test/` instead. Use `UncoveredFunctionalTester` instead of `FunctionalTester`.

### 1. Add Fixture Code

```
spec/uncovered_test/fixtures/{language}/{framework}/
```

### 2. Add a Test Spec

```
spec/uncovered_test/testers/{language}/{framework}_spec.cr
```

Example test spec:
```crystal
require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/items", "GET"),
]

UncoveredFunctionalTester.new("fixtures/{language}/{framework}/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
```

### 3. Run and Verify

```bash
crystal spec spec/uncovered_test/testers/{language}/{framework}_spec.cr
```

## When to Use `uncovered_test/`

- You have identified endpoints that Noir **should** detect but **currently does not**.
- You want to document a known gap without breaking CI.
- You are working on a new analyzer and want to write tests before the implementation is complete.

Once the corresponding analyzer or detector is implemented and the tests pass, move the fixture and test spec from `uncovered_test/` to `functional_test/` (updating the require path and class name from `UncoveredFunctionalTester` to `FunctionalTester`).
