require "../../spec_helper"
require "../../../src/models/skipped_files"

describe Noir::SkippedFiles do
  before_each { Noir::SkippedFiles.clear }
  after_each { Noir::SkippedFiles.clear }

  it "reports nothing when no file was skipped" do
    Noir::SkippedFiles.count.should eq(0)
    Noir::SkippedFiles.failures.should be_empty
  end

  it "tallies one failure per tech, not per file" do
    Noir::SkippedFiles.record("rust_axum", "src/a.rs", "timed out")
    Noir::SkippedFiles.record("rust_axum", "src/b.rs", "no such file")
    Noir::SkippedFiles.record("go_gin", "main.go", "boom")

    Noir::SkippedFiles.count.should eq(3)

    failures = Noir::SkippedFiles.failures
    failures.size.should eq(2)

    axum = failures.find! { |f| f.tech == "rust_axum" }
    axum.message.should contain("skipped 2 files")
    axum.message.should contain("src/a.rs, src/b.rs")
    # The first reason is kept; later ones would just be noise in one line.
    axum.message.should contain("first error: timed out")
  end

  it "uses the singular for one file" do
    Noir::SkippedFiles.record("python_flask", "app.py", "boom")

    Noir::SkippedFiles.failures.first.message.should contain("skipped 1 file:")
  end

  it "caps the example paths and counts the rest" do
    (Noir::SkippedFiles::MAX_PATHS_PER_TECH + 3).times do |i|
      Noir::SkippedFiles.record("java_spring", "Src#{i}.java", "boom")
    end

    message = Noir::SkippedFiles.failures.first.message
    message.should contain("skipped #{Noir::SkippedFiles::MAX_PATHS_PER_TECH + 3} files")
    message.should contain("(+3 more)")
    message.should_not contain("Src#{Noir::SkippedFiles::MAX_PATHS_PER_TECH}.java")
  end

  it "forgets everything on clear, so a second pass starts clean" do
    Noir::SkippedFiles.record("go_gin", "main.go", "boom")
    Noir::SkippedFiles.clear

    Noir::SkippedFiles.count.should eq(0)
    Noir::SkippedFiles.failures.should be_empty
  end

  # The noun is part of the tally key, not decoration. An unlistable directory
  # costs its whole subtree; folding it into the file tally would report the
  # loss of a tree as the loss of one file, and whichever noun arrived first
  # would decide how both read.
  it "keeps a separate tally per noun and pluralizes each correctly" do
    Noir::SkippedFiles.record("detect", "src/app.rb", "unreadable", phase: Noir::SkippedFiles::Phase::Scan)
    Noir::SkippedFiles.record("detect", "src/locked", "permission denied",
      noun: "directory", phase: Noir::SkippedFiles::Phase::Scan)
    Noir::SkippedFiles.record("detect", "src/other", "permission denied",
      noun: "directory", phase: Noir::SkippedFiles::Phase::Scan)

    messages = Noir::SkippedFiles.failures.map(&.message)
    messages.size.should eq(2)
    messages.any?(&.includes?("skipped 1 file:")).should be_true
    messages.any?(&.includes?("skipped 2 directories:")).should be_true
  end

  # Losses with no per-item granularity — an export that never landed, a rule
  # set that loaded nothing — carry their own message and are never merged.
  it "records one entry per gap, verbatim" do
    Noir::SkippedFiles.record_gap("deliver", "webhook delivery to http://x failed: refused")
    Noir::SkippedFiles.record_gap("deliver", "Elasticsearch delivery to http://y failed: refused")

    failures = Noir::SkippedFiles.failures
    failures.size.should eq(2)
    failures.map(&.tech).uniq!.should eq(["deliver"])
    failures.first.message.should eq("webhook delivery to http://x failed: refused")
    # Gaps count no items, so the file tally stays honest.
    Noir::SkippedFiles.count.should eq(0)
  end

  # The two phases exist so `analysis_endpoints` can reset its own pass
  # without erasing what the detection walk already found — a full clear there
  # would drop the walk's gaps before anything reported them.
  it "clears one phase without touching the other" do
    Noir::SkippedFiles.record("detect", "src/locked.rb", "permission denied",
      phase: Noir::SkippedFiles::Phase::Scan)
    Noir::SkippedFiles.record("go_gin", "main.go", "boom",
      phase: Noir::SkippedFiles::Phase::Analysis)
    Noir::SkippedFiles.record_gap("deliver", "webhook never landed")

    Noir::SkippedFiles.clear(Noir::SkippedFiles::Phase::Analysis)

    Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Analysis).should be_empty
    scan_phase = Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Scan)
    scan_phase.map(&.tech).sort!.should eq(["deliver", "detect"])
    Noir::SkippedFiles.failures.size.should eq(2)
  end
end
