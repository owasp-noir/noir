require "../../spec_helper"
require "../../../src/cli/commands/scan"

describe "structured output formats" do
  # A zero-technology scan only calls the output builder for structured
  # formats; each of them emits a well-formed envelope (`paths: {}`,
  # `item: []`, a header-only table, …) for zero endpoints, so dropping one
  # regresses to silent zero-byte output — or, with `-o`, no file at all — on a
  # "no technologies detected" scan.
  #
  # This used to be a hand-maintained `Set` in `Noir::CLI::ScanCommand`: a
  # subset of the derived format catalog, which is the shape that rots
  # silently. It is now declared on the builder as `structured: true` and
  # derived, so the two lists below are the *contract*, not a copy of the
  # implementation — they pin which formats must and must not be in it,
  # whatever mechanism produces the answer.
  it "includes every envelope-style format so a no-endpoint scan still emits a valid empty document" do
    %w[json yaml jsonl toml sarif oas2 oas3 postman html mermaid markdown-table].each do |format|
      Noir::OutputFormats.structured?(format).should be_true
    end
  end

  it "excludes line-list / command formats that have no envelope to render" do
    %w[plain curl httpie powershell adb simctl only-url only-param only-header only-cookie only-tag].each do |format|
      Noir::OutputFormats.structured?(format).should be_false
    end
  end

  # The two lists above name 22 formats, which is every format in the catalog
  # today. If a format is added and classified as neither, that is a decision
  # nobody made — and the consequence (empty output on a zero-endpoint scan) is
  # invisible until a user hits it.
  it "classifies every format in the catalog as structured or not" do
    classified = %w[json yaml jsonl toml sarif oas2 oas3 postman html mermaid markdown-table] +
                 %w[plain curl httpie powershell adb simctl only-url only-param only-header only-cookie only-tag]

    unclassified = Noir::OutputFormats::NAMES - classified

    fail <<-MSG unless unclassified.empty?
      these formats are in the catalog but neither list above says whether a
      zero-endpoint scan should still render them: #{unclassified.sort}.
      Decide, add `structured: true` to the annotation if it emits an
      envelope, and add the name to the matching list here.
      MSG
  end

  # Guards against the annotation being dropped wholesale — an empty set would
  # make the "excludes" example pass vacuously.
  it "derives a non-empty structured set" do
    Noir::OutputFormats::STRUCTURED_NAMES.size.should eq 11
  end
end

describe "Noir::CLI::ScanCommand.host_error" do
  # `-u` is the base URL every discovered path is appended to. Pre-fix
  # only the scheme and the port were validated, so `-u http://` parsed
  # with an empty host and the concatenation promoted the first
  # discovered path segment to the authority (`/a` -> `http://a`) — with
  # `--probe` / `--status-codes` that is a real request at a host the
  # user never named.
  it "rejects a URL with no authority" do
    Noir::CLI::ScanCommand.host_error(URI.parse("http://").host).should eq("has no host")
    Noir::CLI::ScanCommand.host_error(URI.parse("http://:8080").host).should eq("has no host")
    Noir::CLI::ScanCommand.host_error(nil).should eq("has no host")
  end

  it "rejects an authority holding whitespace or control characters" do
    # `-u "not a url"` gets `https://` prepended and then parses with the
    # whole string as the host; the unusable URL reached every endpoint in
    # the JSON/OAS/Postman output.
    whitespace_error = "has whitespace or control characters in the host"
    Noir::CLI::ScanCommand.host_error(URI.parse("https://not a url").host).should eq(whitespace_error)
    Noir::CLI::ScanCommand.host_error(URI.parse("http://a\nb/").host).should eq(whitespace_error)
    Noir::CLI::ScanCommand.host_error("a\tb").should eq(whitespace_error)
    Noir::CLI::ScanCommand.host_error("a b").should eq(whitespace_error)
  end

  it "accepts the host shapes a base URL legitimately takes" do
    [
      "http://localhost:3000", "https://example.com", "https://example.com/api/v1",
      "https://user:pass@example.com:8443/base", "http://127.0.0.1:8080", "http://[::1]:8080",
    ].each do |url|
      Noir::CLI::ScanCommand.host_error(URI.parse(url).host).should be_nil
    end
  end
end

describe "Noir::CLI::ScanCommand.glob_error" do
  # A malformed `--exclude-path` glob is only interpreted deep inside the
  # detector's file walk. `[` at least aborted the scan; every other
  # malformed shape matched nothing at all and exited 0, which reads
  # exactly like an exclusion that worked.
  it "reports an unterminated brace group" do
    Noir::CLI::ScanCommand.glob_error("*.{rb").should eq("unterminated `{` group")
    Noir::CLI::ScanCommand.glob_error("{").should eq("unterminated `{` group")
    Noir::CLI::ScanCommand.glob_error("a{b,c").should eq("unterminated `{` group")
  end

  it "reports an unmatched closing brace" do
    Noir::CLI::ScanCommand.glob_error("}").should eq("unmatched `}`")
    Noir::CLI::ScanCommand.glob_error("*.rb}").should eq("unmatched `}`")
  end

  it "still reports Crystal's own character-class error" do
    Noir::CLI::ScanCommand.glob_error("[").should eq("unterminated character set")
  end

  it "accepts well-formed globs" do
    [
      "*.test.js", "*.{rb,go}", "**/vendor/**", "src/legacy", "[a-z]*.rb",
      "a{b,{c,d}}e", "spec/*_spec.cr",
    ].each do |pattern|
      Noir::CLI::ScanCommand.glob_error(pattern).should be_nil
    end
  end

  it "treats a brace inside a character class as a literal" do
    # `[{]` matches a literal `{` — counting it as a group opener would
    # reject a valid pattern.
    Noir::CLI::ScanCommand.glob_error("[{]").should be_nil
    Noir::CLI::ScanCommand.glob_error("[}]").should be_nil
  end
end

describe "Noir::CLI::ScanCommand.cli_flag_names" do
  # Once the parser has run, a config-file value and a CLI flag are the
  # same entry in the same hash — argv is the only record of what the
  # user actually typed, which is what tells a usage error (`--probe`
  # with no `-u`) from a config key that simply cannot apply this run.
  it "collects long flags, dropping the `=` value" do
    names = Noir::CLI::ScanCommand.cli_flag_names(
      ["scan", "./app", "--probe", "--probe-via=http://127.0.0.1:8080", "-u", "http://x"]
    )
    names.includes?("--probe").should be_true
    names.includes?("--probe-via").should be_true
    names.includes?("-u").should be_true
  end

  it "keeps positionals and flag values out" do
    names = Noir::CLI::ScanCommand.cli_flag_names(["scan", "./app", "-b", "./other"])
    names.includes?("./app").should be_false
    names.includes?("./other").should be_false
    names.includes?("-b").should be_true
  end

  it "is empty for a flagless invocation" do
    Noir::CLI::ScanCommand.cli_flag_names(["scan", "./app"]).empty?.should be_true
  end
end
