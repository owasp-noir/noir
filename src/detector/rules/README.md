# Detector rules

Each YAML file groups one language’s detectors and examples. The filename and top-level entry name give the registry its sort order. For example, the following entry in `Java.yml` sorts alongside the Crystal class names as `Detector::Java::HttpServer`. The `key` is the public technology key. The build embeds the rules into the binary.

```yaml
HttpServer:
  key: java_httpserver
  files: {extensions: [.java]}
  match:
    all:
      - contains: com.sun.net.httpserver
      - contains: createContext
  examples:
    match:
      - {path: Server.java, content: 'com.sun.net.httpserver.HttpServer.create().createContext("/")'}
    no_match:
      - {path: Filter.java, content: 'import com.sun.net.httpserver.Filter;'}
```

## File selection

`files` checks the filename before evaluating the match and also supplies the scanner's applicability gate. A selector accepts any listed extension (a filename suffix), exact basename, or `path_segments` substring. Extensions follow Noir's existing case folding for Windows-oriented stacks. A path segment containing a slash makes an applicability gate path-sensitive.

Use `gate` when the cheap dispatch filter differs from the matcher's filename check. For example, Rust's dispatch filter admits Rust source and manifests, while its Cargo dependency check inspects paths containing `Cargo.toml`. A rule with just `gate` leaves filename checks to its match expression. Within `all` or `any`, a `files` condition restricts a single branch.

A rule can specify a `fallback` with a `match` condition and a `missing_siblings` list of basenames. The scanner evaluates it against the completed file index and logs a possible detection in verbose mode when the listed files are all outside the scan.

## Match conditions

Each condition has one operator. Regex values are PCRE patterns. Use YAML single quotes or a literal block to preserve backslashes.

| Operator | Value and behavior |
| --- | --- |
| `contains` | A literal string or list of alternatives. Matching is case-sensitive. |
| `regex` | A pattern or list of alternative patterns matched against the file contents. Lists compile to one regex union. |
| `all`, `any` | A nonempty list of conditions, evaluated in order with short-circuiting. |
| `not` | One condition. Matches when that condition fails, including a branch-local filename exclusion. |
| `files` | A filename selector, as above. |
| `javascript_import` | A package name used in a JavaScript or TypeScript import, re-export or require call. |
| `json_path` | A path of exact JSON object keys from the root. A list at one level accepts any listed key. |
| `go_dependency` | A regex passed to the shared Go import and direct go.mod dependency check. |
| `go_mod_dependency` | A literal module marker passed to the go.mod check. |
| `cargo_dependency` | A crate name passed to the shared Cargo dependency-key matcher. |
| `ruby_dependency` | A gem name. Paths containing Gemfile use the Gemfile helper. Other paths ending in .gemspec use the gemspec helper. |
| `composer_dependency` | A package name or list passed to the Composer helper. Use a filename selector for the relevant manifests. |
| `package_json_or_ts_import` | A mapping with `package` and `import` regexes for package.json and .ts files respectively. |

Provide at least one `match` and one `no_match` example with `path` and `content`. Use a plausible near miss where possible. Positive examples also exercise dispatch. Optional `applicable` and `inapplicable` lists test the filename gate alone. Run `just spec-build`, then `./bin/noir_spec -e "detector rule examples"`.

Keep detectors that register paths, parse structured documents, or need other procedural checks in Crystal.
