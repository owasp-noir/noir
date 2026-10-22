require "../../spec_helper"
require "file_utils"
require "../../../src/utils/git_snapshot"

private def git!(dir : String, *args : String) : String
  output = IO::Memory.new
  error = IO::Memory.new
  status = Process.run("git", args: ["-C", dir, "-c", "user.email=spec@noir", "-c", "user.name=spec",
                                     "-c", "commit.gpgsign=false"] + args.to_a,
    output: output, error: error)
  raise "git #{args.join(" ")} failed: #{error}" unless status.success?
  output.to_s
end

# A repository with two commits: `app/` and `lib/` at the first, and a new
# file, a changed file and an untracked file on top.
private def with_repo(&)
  root = File.tempname("noir-git-snapshot-spec-")
  Dir.mkdir_p(File.join(root, "app"))
  Dir.mkdir_p(File.join(root, "lib"))
  File.write(File.join(root, "app", "routes.rb"), "get '/old' do\nend\n")
  File.write(File.join(root, "lib", "helper.rb"), "# helper\n")
  git!(root, "init", "-q")
  git!(root, "add", "-A")
  git!(root, "commit", "-q", "-m", "first")
  File.write(File.join(root, "app", "routes.rb"), "get '/new' do\nend\n")
  File.write(File.join(root, "app", "added.rb"), "post '/added' do\nend\n")
  git!(root, "add", "-A")
  git!(root, "commit", "-q", "-m", "second")
  File.write(File.join(root, "app", "untracked.rb"), "# untracked\n")
  yield root
ensure
  FileUtils.rm_rf(root) if root
end

private def with_snapshot(ref : String, bases : Array(String), &)
  snapshot = Noir::GitSnapshot.materialize(ref, bases)
  begin
    yield snapshot
  ensure
    FileUtils.rm_rf(snapshot.root)
  end
end

describe Noir::GitSnapshot do
  it "writes the files a revision tracked, not the working tree" do
    with_repo do |repo|
      with_snapshot("HEAD~1", [repo]) do |snapshot|
        base = snapshot.bases.first
        File.read(File.join(base, "app", "routes.rb")).should contain("/old")
        File.exists?(File.join(base, "app", "added.rb")).should be_false
        File.exists?(File.join(base, "app", "untracked.rb")).should be_false
        File.exists?(File.join(base, "lib", "helper.rb")).should be_true
        snapshot.commit.should eq(git!(repo, "rev-parse", "HEAD~1").strip)
      end
    end
  end

  it "names its checkout with a noir-diff-ref- prefix so a leaked one can be found" do
    with_repo do |repo|
      with_snapshot("HEAD", [repo]) do |snapshot|
        File.basename(snapshot.root).should start_with("noir-diff-ref-")
      end
    end
  end

  it "keeps a leading space in a base directory's name" do
    with_repo do |repo|
      spaced = File.join(repo, " app")
      Dir.mkdir_p(spaced)
      File.write(File.join(spaced, "routes.rb"), "get '/spaced' do\nend\n")
      git!(repo, "add", "-A")
      git!(repo, "commit", "-q", "-m", "spaced")
      with_snapshot("HEAD", [spaced]) do |snapshot|
        base = snapshot.bases.first
        base.should end_with("/ app")
        File.read(File.join(base, "routes.rb")).should contain("/spaced")
      end
    end
  end

  it "maps a base inside the repository to the same place in the snapshot" do
    with_repo do |repo|
      with_snapshot("HEAD~1", [File.join(repo, "app")]) do |snapshot|
        base = snapshot.bases.first
        base.should end_with("/app")
        File.exists?(File.join(base, "routes.rb")).should be_true
        # Only the scanned subtree is written.
        File.exists?(File.join(snapshot.root, "tree", "lib")).should be_false
      end
    end
  end

  it "leaves the repository's HEAD, index and working tree alone" do
    with_repo do |repo|
      head = git!(repo, "rev-parse", "HEAD")
      status = git!(repo, "status", "--porcelain")
      with_snapshot("HEAD~1", [repo]) { }
      git!(repo, "rev-parse", "HEAD").should eq(head)
      git!(repo, "status", "--porcelain").should eq(status)
      File.read(File.join(repo, "app", "routes.rb")).should contain("/new")
    end
  end

  it "works from inside a git hook, which exports GIT_DIR and GIT_INDEX_FILE" do
    with_repo do |repo|
      saved = {"GIT_DIR" => ENV["GIT_DIR"]?, "GIT_INDEX_FILE" => ENV["GIT_INDEX_FILE"]?}
      # What git hands a pre-push hook run from the repository root: both
      # relative, so they break as soon as a call moves into a subdirectory.
      ENV["GIT_DIR"] = ".git"
      ENV["GIT_INDEX_FILE"] = ".git/index"
      begin
        with_snapshot("HEAD~1", [File.join(repo, "app")]) do |snapshot|
          File.read(File.join(snapshot.bases.first, "routes.rb")).should contain("/old")
        end
      ensure
        saved.each { |name, value| value ? (ENV[name] = value) : ENV.delete(name) }
      end
    end
  end

  it "scans a base that did not exist at the revision as an empty directory" do
    with_repo do |repo|
      fresh = File.join(repo, "fresh")
      Dir.mkdir(fresh)
      with_snapshot("HEAD", [fresh]) do |snapshot|
        Dir.exists?(snapshot.bases.first).should be_true
        Dir.children(snapshot.bases.first).should be_empty
      end
    end
  end

  it "rejects a revision that does not exist" do
    with_repo do |repo|
      expect_raises(Noir::GitSnapshot::Error, /does not name a commit/) do
        Noir::GitSnapshot.materialize("no-such-branch", [repo])
      end
    end
  end

  it "rejects a revision that git would read as an option" do
    with_repo do |repo|
      expect_raises(Noir::GitSnapshot::Error, /not an option/) do
        Noir::GitSnapshot.materialize("--output=/tmp/x", [repo])
      end
    end
  end

  it "rejects a base outside any repository" do
    dir = File.tempname("noir-git-snapshot-nogit-")
    Dir.mkdir(dir)
    begin
      expect_raises(Noir::GitSnapshot::Error, /inside a git repository/) do
        Noir::GitSnapshot.materialize("HEAD", [dir])
      end
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "rejects bases spread over two repositories" do
    with_repo do |first|
      with_repo do |second|
        expect_raises(Noir::GitSnapshot::Error, /one git repository/) do
          Noir::GitSnapshot.materialize("HEAD", [first, second])
        end
      end
    end
  end

  it "relocates code paths from the snapshot back to the user's base" do
    snapshot = Noir::GitSnapshot::Snapshot.new(root: "/tmp/snap", commit: "abc",
      bases: ["/tmp/snap/tree/app", "/tmp/snap/tree/app2"])
    endpoints = [
      Endpoint.new("/a", "GET", Details.new(PathInfo.new("/tmp/snap/tree/app/routes.rb", 3))),
      Endpoint.new("/b", "GET", Details.new(PathInfo.new("/tmp/snap/tree/app2/x.rb", 1))),
      Endpoint.new("/c", "GET", Details.new(PathInfo.new("/elsewhere/y.rb", 1))),
    ]

    relocated = snapshot.relocate(endpoints, ["./app", "./app2"])

    relocated.map(&.details.code_paths.first.path).should eq(["./app/routes.rb", "./app2/x.rb", "/elsewhere/y.rb"])
    relocated.first.details.code_paths.first.line.should eq(3)
  end

  it "relocates callee and AI-context paths as well" do
    snapshot = Noir::GitSnapshot::Snapshot.new(root: "/tmp/snap", commit: "abc", bases: ["/tmp/snap/tree/app"])
    endpoint = Endpoint.new("/a", "GET")
    endpoint.push_callee(Callee.new("User.find", "/tmp/snap/tree/app/models/user.rb", 7))
    endpoint.push_callee(Callee.new("helper"))
    context = AIContext.new
    context.sinks << AIContextEntry.new("sink", "exec", path: "/tmp/snap/tree/app/run.rb", line: 2)
    endpoint.ai_context = context

    relocated = snapshot.relocate([endpoint], ["app"]).first

    relocated.callees.map(&.path).should eq(["app/models/user.rb", nil])
    relocated.ai_context.not_nil!.sinks.first.path.should eq("app/run.rb")
  end
end
