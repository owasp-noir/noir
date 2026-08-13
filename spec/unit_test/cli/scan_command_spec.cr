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
