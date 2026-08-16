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
end
