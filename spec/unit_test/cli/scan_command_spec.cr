require "../../spec_helper"
require "../../../src/cli/commands/scan"

describe Noir::CLI::ScanCommand do
  describe "STRUCTURED_OUTPUT_FORMATS" do
    # A zero-technology scan only calls the output builder for formats in
    # this set; every format below already emits a well-formed envelope
    # (paths: {}, item: [], header-only table, ...) for zero endpoints, so
    # skipping any of them here regresses to silent zero-byte output (or,
    # with `-o`, no file at all) on a "no technologies detected" scan.
    it "includes every envelope-style format so a no-endpoint scan still emits a valid empty document" do
      %w[json yaml jsonl toml sarif oas2 oas3 postman html mermaid markdown-table].each do |format|
        Noir::CLI::ScanCommand::STRUCTURED_OUTPUT_FORMATS.includes?(format).should be_true
      end
    end

    it "excludes line-list / command formats that have no envelope to render" do
      %w[plain curl httpie powershell adb simctl only-url only-param only-header only-cookie only-tag].each do |format|
        Noir::CLI::ScanCommand::STRUCTURED_OUTPUT_FORMATS.includes?(format).should be_false
      end
    end
  end
end
