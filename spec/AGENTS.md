# AGENTS.md - Guide for Adding Tests

This document explains the test directory structure and how to add new test cases.

## Directory Structure

```
spec/
├── spec_helper.cr              # Shared test helpers
├── noir_spec.cr                # Main spec entry point
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
just test              # Run all CI tests (unit + functional)
just test-unit         # Run unit tests only
just test-func         # Run functional tests only
just test-uncovered    # Run uncovered tests only (not in CI)
```

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
