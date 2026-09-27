require "file_utils"
require "../models/endpoint"

module Noir
  # Materializes the files a git revision tracked into a scratch directory,
  # so `--diff-ref REF` can scan the old side of a diff without the user
  # checking it out first.
  #
  # The checkout goes through a private index (`GIT_INDEX_FILE`) and
  # `checkout-index --prefix`, which is plumbing: it writes files and nothing
  # else. The user's HEAD, index and working tree are never touched, no ref
  # moves, and no hook runs — `git checkout <ref> -- <path>` would have fired
  # `post-checkout`, `git worktree add` leaves an entry in `.git/worktrees`
  # that outlives a crashed scan.
  module GitSnapshot
    class Error < Exception
    end

    # `root` is the scratch directory to delete when the scan is done;
    # `bases[i]` is where the old side of `base_paths[i]` lives inside it.
    record Snapshot, root : String, commit : String, bases : Array(String) do
      # Rewrites every code path under `bases[i]` to sit under
      # `originals[i]` instead, so endpoints scanned out of the scratch
      # checkout name the file where the user would look for it.
      def relocate(endpoints : Array(Endpoint), originals : Array(String)) : Array(Endpoint)
        pairs = bases.zip(originals).sort_by! { |pair| -pair[0].size }
        endpoints.map do |endpoint|
          details = endpoint.details
          details.code_paths = details.code_paths.map do |info|
            PathInfo.new(relocate_path(info.path, pairs), info.line)
          end
          endpoint.details = details
          endpoint
        end
      end

      private def relocate_path(path : String, pairs : Array({String, String})) : String
        pairs.each do |(from, to)|
          return to if path == from
          return File.join(to, path[from.size + 1..]) if path.starts_with?(from) && path[from.size]? == '/'
        end
        path
      end
    end

    extend self

    def materialize(ref : String, base_paths : Array(String)) : Snapshot
      raise Error.new("--diff-ref needs a git revision, got an empty value") if ref.empty?
      # Every call below passes `ref` as an argument, and git reads a leading
      # dash as an option there, not as a revision name.
      raise Error.new("--diff-ref must name a git revision, not an option: #{ref}") if ref.starts_with?('-')

      toplevel = repository_root(base_paths)
      commit = resolve_commit(toplevel, ref)
      relatives = base_paths.map { |base| relative_to_root(base, toplevel) }

      root = File.tempname("noir-diff-ref-")
      Dir.mkdir(root, 0o700)
      begin
        tree = File.join(root, "tree")
        Dir.mkdir(tree)
        checkout(toplevel, commit, relatives, File.join(root, "index"), tree)
        bases = relatives.map do |relative|
          path = relative.empty? ? tree : File.join(tree, relative)
          # A base that did not exist at REF is a real answer — everything
          # under it is new — so it scans as an empty directory rather than
          # failing the run.
          Dir.mkdir_p(path) unless File.exists?(path)
          path
        end
        Snapshot.new(root: root, commit: commit, bases: bases)
      rescue e
        FileUtils.rm_rf(root)
        raise e
      end
    end

    # Every base has to sit in one repository: REF names a commit of a
    # specific repository, and two roots would make it ambiguous which.
    private def repository_root(base_paths : Array(String)) : String
      roots = base_paths.map do |base|
        dir = File.directory?(base) ? base : File.dirname(base)
        result = git(["-C", dir, "rev-parse", "--show-toplevel"])
        unless result[:ok]
          raise Error.new("--diff-ref needs the scan path to be inside a git repository: #{base}#{detail(result[:error])}")
        end
        result[:output].strip
      end.uniq!

      if roots.size > 1
        raise Error.new("--diff-ref needs every base path inside one git repository, found #{roots.size}: #{roots.join(", ")}")
      end
      roots.first
    end

    private def resolve_commit(toplevel : String, ref : String) : String
      result = git(["-C", toplevel, "rev-parse", "--verify", "--quiet", "#{ref}^{commit}"])
      return result[:output].strip if result[:ok]

      message = "--diff-ref #{ref} does not name a commit in #{toplevel}"
      if git(["-C", toplevel, "rev-parse", "--is-shallow-repository"])[:output].strip == "true"
        # The default `actions/checkout` is a depth-1 clone, which is where
        # this is hit first. Say so instead of leaving a bare "unknown ref".
        message += " (this is a shallow clone; fetch the revision first, e.g. `git fetch origin #{ref}` or actions/checkout with `fetch-depth: 0`)"
      end
      raise Error.new(message)
    end

    # The path of `base` relative to the repository root, "" for the root
    # itself. Git reports the root as a real path, so the base is resolved the
    # same way before comparing — on macOS `/tmp` is `/private/tmp`, and
    # comparing the spelled path against the real one would put every base
    # outside the repository.
    private def relative_to_root(base : String, toplevel : String) : String
      real = File.realpath(base)
      return "" if real == toplevel
      prefix = toplevel.ends_with?('/') ? toplevel : "#{toplevel}/"
      unless real.starts_with?(prefix)
        raise Error.new("--diff-ref base path is outside the repository #{toplevel}: #{base}")
      end
      real[prefix.size..]
    end

    # Reads REF's tree into a private index, lists the files under the scan
    # bases from it, and writes just those under `tree`. Listing first keeps
    # a scan of one package in a large monorepo from writing the whole
    # repository to disk.
    private def checkout(toplevel : String, commit : String, relatives : Array(String),
                         index : String, tree : String) : Nil
      env = {"GIT_INDEX_FILE" => index}

      result = git(["-C", toplevel, "read-tree", commit], env: env)
      raise Error.new("could not read the tree of #{commit}#{detail(result[:error])}") unless result[:ok]

      pathspecs = relatives.any?(&.empty?) ? ["."] : relatives
      # `:(literal)` so a directory named `*` or `[a]` is a path, not a glob.
      args = ["-C", toplevel, "ls-files", "-z", "--"] + pathspecs.map { |p| ":(literal)#{p}" }
      listed = git(args, env: env)
      raise Error.new("could not list the files of #{commit}#{detail(listed[:error])}") unless listed[:ok]
      return if listed[:output].empty?

      # `--prefix` is a string prefix, not a directory, so it needs the
      # trailing separator. `-f` because the scratch tree is ours.
      written = git(["-C", toplevel, "checkout-index", "-z", "--stdin", "-f", "--prefix=#{tree}/"],
        env: env, input: listed[:output])
      raise Error.new("could not write the files of #{commit}#{detail(written[:error])}") unless written[:ok]
    end

    private def git(args : Array(String), env : Hash(String, String)? = nil, input : String? = nil)
      output = IO::Memory.new
      error = IO::Memory.new
      status = Process.run("git", args: args, env: env, output: output, error: error,
        input: input ? IO::Memory.new(input) : Process::Redirect::Close)
      {ok: status.success?, output: output.to_s, error: error.to_s}
    rescue e : File::NotFoundError | IO::Error
      raise Error.new("--diff-ref needs git on PATH (#{e.message})")
    end

    private def detail(stderr : String) : String
      line = stderr.lines.map(&.strip).reject(&.empty?).first?
      line ? ": #{line}" : ""
    end
  end
end
