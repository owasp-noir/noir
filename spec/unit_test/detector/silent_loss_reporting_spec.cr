require "file_utils"
require "../../spec_helper"
require "../../../src/detector/detector"
require "../../../src/models/analyzer"
require "../../../src/models/code_locator"
require "../../../src/models/logger"
require "../../../src/models/skipped_files"
require "../../../src/utils/media_filter"

# Everything the detection walk drops must be visible in `errors`.
#
# The walk has four ways to lose a file and every one of them used to be
# invisible: an unlistable directory took its whole subtree through an *empty*
# rescue body, an oversize / unreadable / binary-looking file was counted into
# a local `Int32` and forgotten, and a symlink was skipped before the file
# counter even ran. A scan that lost most of a code base was byte-identical to
# one that read everything — `"errors": []`, exit 0 — which is what made
# `--strict` in CI a green light over a hole.
#
# These drive `detect_techs` and read the channel it feeds, because that is
# the boundary the CLI reads too: `NoirRunner#detect` snapshots exactly this
# list into `analyzer_failures`, which is what `errors` and the `--strict`
# exit code are computed from.
private def scan_gaps(dir : String) : Array(AnalyzerFailure)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  logger = NoirLogger.new(false, false, false, true)
  CodeLocator.instance.clear_all
  detect_techs([dir], options, [] of PassiveScan, logger)
  Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Scan)
end

# Mode bits do not apply to root, and a spec that cannot establish the
# condition it tests must say so rather than pass.
private def readable_despite_chmod?(path : String) : Bool
  if File.directory?(path)
    Dir.each_child(path) { |_| break }
  else
    File.read(path)
  end
  true
rescue File::Error
  false
end

describe "detection walk coverage reporting" do
  before_each { Noir::SkippedFiles.clear }
  after_each do
    Noir::SkippedFiles.clear
    CodeLocator.instance.clear_all
  end

  it "reports a directory it could not list, and everything under it" do
    temp_dir = File.tempname("noir_unlistable_dir")
    locked = File.join(temp_dir, "sub")
    Dir.mkdir_p(locked)

    begin
      File.write(File.join(temp_dir, "Gemfile"), "gem 'sinatra'\n")
      File.write(File.join(temp_dir, "app.rb"), "require 'sinatra'\nget '/root' do\nend\n")
      3.times do |i|
        File.write(File.join(locked, "a#{i}.rb"), "require 'sinatra'\nget '/sub#{i}' do\nend\n")
      end
      File.chmod(locked, 0o000)
      pending! "requires a non-root user: mode 000 is not enforced here" if readable_despite_chmod?(locked)

      gaps = scan_gaps(temp_dir)

      gaps.size.should eq(1)
      gaps.first.tech.should eq(Noir::SkippedFiles::DETECT_SCOPE)
      # "directory", not "file": three source files went with it, and calling
      # the loss a single file would understate it by the size of the subtree.
      gaps.first.message.should contain("skipped 1 directory")
      gaps.first.message.should contain(locked)
    ensure
      File.chmod(locked, 0o755) if File.exists?(locked)
      FileUtils.rm_rf(temp_dir)
    end
  end

  it "reports a source file it could not read" do
    temp_dir = File.tempname("noir_unreadable_file")
    Dir.mkdir_p(temp_dir)
    locked = File.join(temp_dir, "locked.py")

    begin
      File.write(File.join(temp_dir, "app.py"), "from flask import Flask\napp = Flask(__name__)\n")
      File.write(locked, "from flask import Flask\n\n@app.route('/locked')\ndef locked():\n    pass\n")
      File.chmod(locked, 0o000)
      pending! "requires a non-root user: mode 000 is not enforced here" if readable_despite_chmod?(locked)

      gaps = scan_gaps(temp_dir)

      gaps.size.should eq(1)
      gaps.first.tech.should eq(Noir::SkippedFiles::DETECT_SCOPE)
      gaps.first.message.should contain("skipped 1 file")
      gaps.first.message.should contain(locked)
    ensure
      File.chmod(locked, 0o644) if File.exists?(locked)
      FileUtils.rm_rf(temp_dir)
    end
  end

  it "reports a source file it skipped for being over the size ceiling" do
    temp_dir = File.tempname("noir_oversize_file")
    Dir.mkdir_p(temp_dir)

    begin
      File.write(File.join(temp_dir, "app.py"), "from flask import Flask\napp = Flask(__name__)\n")
      huge = File.join(temp_dir, "huge.py")
      File.open(huge, "w") do |io|
        io << "from flask import Flask\n\n@app.route('/big')\ndef big():\n    pass\n"
        padding = "# pad\n" * 1024
        ((MediaFilter::MAX_FILE_SIZE // padding.bytesize) + 1).times { io << padding }
      end

      gaps = scan_gaps(temp_dir)

      gaps.size.should eq(1)
      gaps.first.tech.should eq(Noir::SkippedFiles::DETECT_SCOPE)
      gaps.first.message.should contain(huge)
      gaps.first.message.should contain("file too large")
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  it "reports a text-extension file whose bytes look binary" do
    temp_dir = File.tempname("noir_binary_file")
    Dir.mkdir_p(temp_dir)

    begin
      File.write(File.join(temp_dir, "app.py"), "from flask import Flask\napp = Flask(__name__)\n")
      blob = File.join(temp_dir, "blob.py")
      # NUL in the body, so `skip_check`'s extension/size pass lets it
      # through and the post-read sniff is what drops it.
      File.write(blob, "from flask import Flask\n\u0000\u0000\u0000binary\n")

      gaps = scan_gaps(temp_dir)

      gaps.size.should eq(1)
      gaps.first.message.should contain(blob)
      gaps.first.message.should contain("binary content")
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  it "reports symlinks it did not follow" do
    temp_dir = File.tempname("noir_symlink_walk")
    inside = File.join(temp_dir, "inside")
    outside = File.join(temp_dir, "outside")
    Dir.mkdir_p(inside)
    Dir.mkdir_p(outside)

    begin
      File.write(File.join(temp_dir, "Gemfile"), "gem 'sinatra'\n")
      File.write(File.join(inside, "a.rb"), "require 'sinatra'\nget '/inside' do\nend\n")
      File.write(File.join(outside, "b.rb"), "require 'sinatra'\nget '/outside' do\nend\n")
      # A directory symlink and a file symlink: the two shapes a pnpm /
      # Bazel workspace produces, and neither is a `file?` to `File.info?`
      # with `follow_symlinks: false`.
      File.symlink(outside, File.join(temp_dir, "ext"))
      File.symlink(File.join(outside, "b.rb"), File.join(temp_dir, "extfile.rb"))

      gaps = scan_gaps(temp_dir)

      gaps.size.should eq(1)
      gaps.first.message.should contain("skipped 2 entries")
      gaps.first.message.should contain("symbolic link (not followed)")
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  # The other half of the contract, and the easier one to break: a scan with
  # nothing wrong with it must stay silent. Media files and pruned dependency
  # trees are the filter working as designed, not coverage the user lost — if
  # they were reported, every repository with a PNG in it would fail
  # `--strict`.
  it "stays silent on a clean scan, including media files and pruned trees" do
    temp_dir = File.tempname("noir_clean_walk")
    Dir.mkdir_p(File.join(temp_dir, "node_modules", "left-pad"))
    Dir.mkdir_p(File.join(temp_dir, "app"))

    begin
      File.write(File.join(temp_dir, "Gemfile"), "gem 'sinatra'\n")
      File.write(File.join(temp_dir, "app", "app.rb"), "require 'sinatra'\nget '/root' do\nend\n")
      File.write(File.join(temp_dir, "logo.png"), "PNG\r\n\n not really a png")
      File.write(File.join(temp_dir, "node_modules", "left-pad", "index.js"), "module.exports = 1\n")
      # A symlink to a pruned dependency tree is the shape pnpm workspaces
      # produce by the hundred; it must not read as lost coverage either.
      File.symlink(File.join(temp_dir, "node_modules", "left-pad"), File.join(temp_dir, "app", "node_modules"))

      scan_gaps(temp_dir).should be_empty
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end
end
