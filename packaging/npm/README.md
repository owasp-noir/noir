# OWASP Noir

Hunt every endpoint in your code, expose shadow APIs, and map the attack surface.

[OWASP Noir](https://github.com/owasp-noir/noir) finds API endpoints, web pages and other entry points by static analysis of source code across many languages and frameworks. This package installs the `noir` command.

## Install

```bash
npm install -g @owasp-noir/noir
noir --version
```

Or run it once without installing:

```bash
npx @owasp-noir/noir -b ./my-app
```

The package downloads the Noir release binary for your platform during install and refuses it unless its SHA-256 matches the one pinned in the package. Supported platforms: Linux and macOS on x86_64 and arm64. On Windows, and for other install options, see the [installation guide](https://owasp-noir.github.io/noir/get_started/installation/).

If your package manager skips install scripts (pnpm, bun, or npm with `--ignore-scripts`), allow it for this package: `pnpm approve-builds`, `bun pm trust @owasp-noir/noir`, or `npm rebuild @owasp-noir/noir`.

## Usage

```bash
noir -b .                 # scan the current directory
noir -b . -f json         # JSON output
noir -b . -P              # passive security scan
noir -h                   # all options
```

Documentation: <https://owasp-noir.github.io/noir/>

## License

MIT
