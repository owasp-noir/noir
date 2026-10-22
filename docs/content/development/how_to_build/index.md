+++
title = "How to Build"
description = "Set up a development environment, build from source, run tests, and contribute to OWASP Noir."
weight = 1
sort_by = "weight"

+++

How to send a change, set up Crystal, build Noir, and run the tests and linter.

{% mascot(mood="good") %}
Fixes, features, docs, fixtures: every kind of contribution moves Noir forward. Thanks for being here.
{% end %}

## How to Contribute

1.  **Fork** the [Noir repository](https://github.com/owasp-noir/noir)
2.  **Create a branch**
    ```sh
    git checkout -b your-feature-name
    ```
3.  **Make changes**
4.  **Commit** with a clear message
5.  **Push** to your fork
    ```sh
    git push origin your-feature-name
    ```
6.  **Open a Pull Request** with a description

See [CONTRIBUTING.md](https://github.com/owasp-noir/noir/blob/main/.github/CONTRIBUTING.md) for detailed guidelines.

## Development Setup

### Installing Crystal

Noir is built with Crystal (`~> 1.19` in `shard.yml`; CI tests on 1.21 and 1.22). Install it for your platform. The first build also compiles the vendored Tree-sitter grammars, so you need a C compiler too.

#### Ubuntu/Debian
```sh
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
sudo apt install -y libyaml-dev libzstd-dev zlib1g-dev pkg-config
```

#### macOS (Homebrew)
```sh
brew install crystal
```

#### Other Platforms
See the [official Crystal installation guide](https://crystal-lang.org/install/).

### Building and Testing

Clone your fork and install dependencies with `shards`, Crystal's package manager.

```sh
git clone https://github.com/<YOUR-USERNAME>/noir
cd noir
shards install
```

Build the project. The compiled binary ends up at `./bin/noir`.

```sh
shards build
```

For a production-grade build (slower compile, 2–3× faster runtime), pass `--release`. Use it when you run benchmarks or compare against a published release. Debug builds are noticeably slower and can make a healthy build look like a regression. The `just` recipe uses the same flags as the official release builds (`--release --no-debug --production`).

```sh
shards build --release
# or use the just recipe (alias: `just br`)
just build-release
```

Run the test suite. `just test` compiles the unit and functional suites into one binary (`bin/noir_spec`) and runs both halves in parallel.

```sh
just test

# One functional tester while you work on an analyzer
just test-func-one javascript/hono

# Or Crystal's built-in test runner
crystal spec
crystal spec -v
```

### Linting

Noir uses [Ameba](https://github.com/crystal-ameba/ameba), a static analysis tool for Crystal.

```sh
lib/ameba/bin/ameba.cr
```

Auto-fix issues.

```sh
lib/ameba/bin/ameba.cr --fix
```

Or use `just`. `just fix` formats and auto-fixes; `just check` only reports, the same way CI does.

```sh
just fix
just check
```
