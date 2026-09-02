require "file_utils"
require "../../spec_helper"
require "../../../src/detector/detector"
require "../../../src/models/analyzer"
require "../../../src/models/code_locator"
require "../../../src/models/locator_keys"
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

# One segment of the over-PATH_MAX tree below. 200 chars is under NAME_MAX
# (255) on every filesystem the CI runs on, so 30 of them clear the 4096-byte
# Linux limit with room to spare.
private DEEP_SEGMENT = "d" * 200

private DEEP_TREE_LEVELS = 30

# Builds `levels` nested directories under `root` and writes `leaf` at the
# bottom, stepping the working directory down as it goes: a single
# `Dir.mkdir_p` of the full path would hit the very wall this exercises.
private def build_deep_tree(root : String, levels : Int32, leaf : String, contents : String) : String
  Dir.mkdir_p(root)
  previous = Dir.current
  begin
    Dir.cd(root)
    levels.times do
      Dir.mkdir(DEEP_SEGMENT)
      Dir.cd(DEEP_SEGMENT)
    end
    File.write(leaf, contents)
    File.join(Dir.current, leaf)
  ensure
    Dir.cd(previous)
  end
end

# `FileUtils.rm_rf` walks with absolute paths and so cannot reach past
# `PATH_MAX` either; unwind the same way it was built.
private def remove_deep_tree(root : String, levels : Int32, leaf : String) : Nil
  return unless Dir.exists?(root)
  previous = Dir.current
  begin
    Dir.cd(root)
    levels.times { Dir.cd(DEEP_SEGMENT) }
    File.delete?(leaf)
    levels.times do
      Dir.cd("..")
      Dir.delete(DEEP_SEGMENT)
    end
  rescue File::Error
    # Best effort: a partially built tree leaves the rest to the tmp reaper.
  ensure
    Dir.cd(previous)
  end
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

  # The other side of that ceiling. An oversize `.py` is a generated blob and
  # skipping it is the filter working; an oversize `openapi.json` is the
  # document the scan exists to read. NetBox ships a 12.35MB
  # `contrib/openapi.json` with 308 paths in it, and the media cap dropped
  # every one of them.
  it "reads an oversize specification document instead of reporting it as a gap" do
    temp_dir = File.tempname("noir_oversize_spec")
    Dir.mkdir_p(temp_dir)

    begin
      spec_path = File.join(temp_dir, "openapi.json")
      # Padded in the description of a real path, so the document stays valid
      # OpenAPI at more than MAX_FILE_SIZE bytes — the shape a generated spec
      # with thousands of schemas arrives in.
      padding = "generated schema documentation. " * 512
      File.open(spec_path, "w") do |io|
        io << %({"openapi":"3.0.3","info":{"title":"Big","version":"1"},"paths":{"/oversize":{"get":{"description":")
        ((MediaFilter::MAX_FILE_SIZE // padding.bytesize) + 1).times { io << padding }
        io << %(","responses":{"200":{"description":"ok"}}}}}})
      end

      gaps = scan_gaps(temp_dir)

      gaps.should be_empty
      CodeLocator.instance.all(Noir::LocatorKeys::OAS3_JSON).should contain(spec_path)
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

  # `File.info?` answers `nil` for every `stat(2)` failure, and the walk used
  # to `next` on that without a word — no counter, no log line, no `errors`
  # entry. The reachable case is a path longer than `PATH_MAX`: a generated
  # or vendored tree crosses the limit (4096 bytes on Linux, 1024 on macOS)
  # a few dozen levels down, and from there every entry stats
  # `ENAMETOOLONG`. A 1000-level tree therefore reported zero endpoints,
  # `"errors": []` and exit 0 under `--strict` — the same output as a clean
  # scan of an empty directory, for a subtree that was never looked at.
  it "reports an entry it could not stat, and everything under it" do
    temp_dir = File.tempname("noir_unstattable_entry")
    Dir.mkdir_p(temp_dir)

    begin
      File.write(File.join(temp_dir, "Gemfile"), "gem 'sinatra'\n")
      File.write(File.join(temp_dir, "app.rb"), "require 'sinatra'\nget '/root' do\nend\n")

      deep_root = File.join(temp_dir, "deep")
      leaf = build_deep_tree(deep_root, DEEP_TREE_LEVELS,
        "buried.rb", "require 'sinatra'\nget '/buried' do\nend\n")
      # A filesystem or platform that resolves the whole path is not the
      # condition under test.
      pending! "path longer than PATH_MAX is still resolvable here" unless File.info?(leaf, follow_symlinks: false).nil?

      gaps = scan_gaps(temp_dir)

      gaps.size.should eq(1)
      gaps.first.tech.should eq(Noir::SkippedFiles::DETECT_SCOPE)
      gaps.first.message.should contain("skipped 1 unreadable entry")
    ensure
      remove_deep_tree(File.join(temp_dir, "deep"), DEEP_TREE_LEVELS, "buried.rb")
      FileUtils.rm_rf(temp_dir)
    end
  end

  # A spec document the detector could not parse at all.
  #
  # The spec detectors wrap "parse, then check the root key" in one `rescue`
  # and used to log both halves at `--debug` and nothing more. The shape
  # check failing is the gate working — the file is simply not an OpenAPI
  # document — but a `JSON::ParseException` means nothing can read the file,
  # so it is never registered, no analyzer ever opens it, and every endpoint
  # it declares is lost. Crystal's `JSON.parse` refuses at 512 levels of
  # nesting, and a truncated download fails far sooner than that.
  it "reports a specification document it could not parse" do
    temp_dir = File.tempname("noir_unparsable_spec")
    Dir.mkdir_p(temp_dir)

    begin
      spec_path = File.join(temp_dir, "openapi.json")
      # Valid OpenAPI apart from one sibling key nested past the parser's
      # ceiling, so the marker matches and the parse is what fails.
      File.write(spec_path, String.build do |io|
        io << %({"openapi":"3.0.3","info":{"title":"Deep","version":"1"},)
        io << %("paths":{"/deep":{"get":{"responses":{"200":{"description":"ok"}}}}},)
        io << %("x-deep":)
        600.times { io << %({"a":) }
        io << "1"
        600.times { io << "}" }
        io << "}"
      end)

      gaps = scan_gaps(temp_dir)

      gaps.size.should eq(1)
      gaps.first.tech.should eq("oas3")
      gaps.first.message.should contain("skipped 1 unparsable document")
      gaps.first.message.should contain(spec_path)
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  # And the other half: a document that parses but is not the format must
  # stay silent. `"openapi": "3.0.0"` nested inside a wrapper document makes
  # the marker match and `data["openapi"]` raise `KeyError` — the gate doing
  # its job. Reporting that would put an entry in `errors` for every file
  # that mentions OpenAPI in passing.
  it "stays silent on a parsable document that is not the format" do
    temp_dir = File.tempname("noir_wrong_shape_spec")
    Dir.mkdir_p(temp_dir)

    begin
      File.write(File.join(temp_dir, "meta.json"),
        %({"upstream":{"openapi":"3.0.0"},"note":"not a spec document"}))

      scan_gaps(temp_dir).should be_empty
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
