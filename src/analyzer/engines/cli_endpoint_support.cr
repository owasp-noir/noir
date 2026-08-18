require "../../models/endpoint"

# Shared by the 21 `src/analyzer/analyzers/{lang}/cli.cr` analyzers, which all
# build the same thing: a set of `cli://<binary>` endpoints, one per
# (sub)command, so that flags and env vars discovered in different files merge
# onto one command.
#
# It is a mixin rather than an inherited method because the CLI analyzers have
# no common base below `Analyzer`: 17 extend `Analyzer` directly, while the Go,
# JavaScript, Python and Ruby ones extend their language engine. Pushing this
# onto `Analyzer` itself would hand a `cli://`-specific constructor to all ~200
# analyzers, so the mixin is included by exactly the 21 that want it.
#
# The other helpers those files carry — `cli_test_path?`, `<lang>_binary_name`,
# `cli_evidence?` — each read a per-class constant whose *value* differs by
# language (Perl's test tree is `/t/`, Scala's is `/it/`, Groovy's is
# `spec.groovy`; the binary-name stem lists disagree too). Several are
# therefore textually identical while resolving to different regexes, so
# folding them on name would be a silent behaviour change. They stay where
# they are — but the *fallback* half of `<lang>_binary_name`, which is genuine
# duplication, lives here as `cli_directory_binary_name`.
module CliEndpointSupport
  # Separator inside the endpoint-map key. A NUL can appear in neither a path
  # nor a URL, so the three parts of the key (configured base, project
  # directory, URL) can never be confused for one another.
  KEY_SEP = Char::ZERO

  # Directory names that describe a project's layout rather than name the
  # program inside it.
  CLI_LAYOUT_DIRS = Set{
    "src", "source", "sources", "bin", "cmd", "cmds", "command", "commands",
    "lib", "libs", "app", "apps", "main", "cli", "script", "scripts",
    "tool", "tools", "internal", "pkg", "exe", "console", "program",
    "programs", "code", "packages", "project", "projects", "test", "tests",
  }

  # Files that mark a project root. A CLI file's nearest enclosing manifest is
  # the program it belongs to; two files under different manifests are two
  # programs even when their inferred binary names collide.
  #
  # Deliberately excludes `CMakeLists.txt` / `meson.build`: those are written
  # per *subdirectory* in a normal build tree, so they mark layout rather than
  # a project boundary and would split one program into many.
  CLI_MANIFEST_BASENAMES = %w[
    shard.yml go.mod Cargo.toml package.json deno.json deno.jsonc jsr.json
    pubspec.yaml mix.exs build.sbt build.sc pom.xml build.gradle
    build.gradle.kts settings.gradle settings.gradle.kts composer.json
    pyproject.toml setup.py setup.cfg Pipfile Gemfile stack.yaml package.yaml
    cabal.project deps.edn project.clj bb.edn Package.swift build.zig
    build.zig.zon cpanfile Makefile.PL dist.ini
  ]

  # Manifests named after the project rather than by a fixed basename.
  CLI_MANIFEST_EXTENSIONS = %w[.cabal .csproj .fsproj .vbproj .gemspec .rockspec .nimble]

  # Fetches (or lazily creates) the endpoint for a URL, so flags scattered
  # across files/blocks merge onto one command.
  #
  # Merging is keyed on the URL *within one project*, never globally. The URL
  # comes from `<lang>_binary_name`, which for a generic stem (`main`, `cli`,
  # `app`, `Program`, ...) falls back to a directory name — so in a monorepo
  # two unrelated binaries could land on the same URL and collapse into a
  # single endpoint carrying both flag sets, with only the first file's
  # `code_path` to show for it.
  private def fetch_endpoint(endpoints : Hash(String, Endpoint), url : String,
                             path : String, line_no : Int32) : Endpoint
    endpoint = endpoints[cli_endpoint_key(path, url)] ||= begin
      ep = Endpoint.new(url, "CLI", Details.new(PathInfo.new(path, line_no)))
      ep.protocol = "cli"
      ep
    end

    # Every file that contributed a flag, argument or env var to this command
    # is part of its definition. Recording only the first made a merge across
    # files invisible in the output.
    unless endpoint.details.code_paths.any? { |code_path| code_path.path == path }
      endpoint.details.add_path(PathInfo.new(path, line_no))
    end

    endpoint
  end

  # Collects what `fetch_endpoint` built, disambiguating any URL that two
  # different projects both claim. Every CLI analyzer ends its `analyze` with
  # this instead of draining the hash directly.
  #
  # Keying the map per project is not enough on its own: the optimizer dedups
  # endpoints by (method, url) and merges their params, so two same-named
  # binaries in one monorepo would be stitched back into a single command
  # carrying both flag sets no matter how the analyzer kept them apart.
  # Prefixing the contested projects' URLs with their base-relative project
  # path keeps them distinct all the way to the output.
  #
  # Order-independent: which URLs are contested depends only on the *set* of
  # (project, url) pairs, so a scan always produces the same URLs.
  private def cli_endpoints(endpoints : Hash(String, Endpoint)) : Array(Endpoint)
    projects_by_url = Hash(String, Set(String)).new
    endpoints.each do |key, endpoint|
      (projects_by_url[endpoint.url] ||= Set(String).new) << cli_key_project(key)
    end

    contested = Set(String).new
    projects_by_url.each_value { |projects| contested.concat(projects) if projects.size > 1 }

    result = [] of Endpoint
    endpoints.each do |key, endpoint|
      prefix = cli_key_project_path(key)
      if !prefix.empty? && contested.includes?(cli_key_project(key))
        endpoint.url = endpoint.url.sub("cli://", "cli://#{prefix}/")
      end
      result << endpoint
    end
    result
  end

  private def cli_endpoint_key(path : String, url : String) : String
    base, dir = cli_project_scope(path)
    "#{base}#{KEY_SEP}#{dir}#{KEY_SEP}#{url}"
  end

  # The `base + project directory` half of an endpoint key.
  private def cli_key_project(key : String) : String
    index = key.rindex(KEY_SEP)
    index ? key[0, index] : key
  end

  # The project directory half of an endpoint key, ready to prefix a URL with.
  private def cli_key_project_path(key : String) : String
    parts = key.split(KEY_SEP)
    parts.size >= 2 ? parts[1].strip('/') : ""
  end

  # The project a CLI file belongs to: the nearest enclosing directory holding
  # a project manifest, qualified by the configured base that owns the file so
  # two bases with the same internal layout stay apart. Falls back to the base
  # root when the scan holds no manifest above the file — a bare script
  # directory is one project.
  private def cli_project_scope(path : String) : Tuple(String, String)
    roots = cli_manifest_dirs
    base = configured_base_for(path)
    dir = File.dirname(base_relative_path(path))

    loop do
      return {base, dir} if roots.includes?("#{base}#{KEY_SEP}#{dir}")
      break if dir.empty? || dir == "/" || dir == "."
      dir = File.dirname(dir)
    end

    {base, ""}
  end

  @cli_manifest_dirs : Set(String)?

  # Base-relative directories holding a project manifest, qualified by their
  # configured base. Built from the basename/extension indexes rather than a
  # walk of `all_files`, so this costs a handful of hash lookups per analyzer.
  private def cli_manifest_dirs : Set(String)
    @cli_manifest_dirs ||= begin
      dirs = Set(String).new
      CLI_MANIFEST_BASENAMES.each do |basename|
        get_files_by_basename(basename).each { |file| dirs << cli_manifest_dir_key(file) }
      end
      CLI_MANIFEST_EXTENSIONS.each do |extension|
        get_files_by_extension(extension).each { |file| dirs << cli_manifest_dir_key(file) }
      end
      dirs
    end
  end

  private def cli_manifest_dir_key(file : String) : String
    "#{configured_base_for(file)}#{KEY_SEP}#{File.dirname(base_relative_path(file))}"
  end

  # Shared fallback for every `<lang>_binary_name`: the program's name when
  # the file stem is a generic entry point (`main`, `cli`, `app`, `Program`,
  # `core`, `__main__`, ...) and so names nothing.
  #
  # Every one of those methods used to take the *immediate* parent directory,
  # which is how `mono/alpha/src/main.cr` and `mono/beta/src/main.cr` both
  # became `cli://src`. Walk up past directories that describe layout instead,
  # and stop at the scan base rather than climbing out of the project.
  #
  # Returns nil only when nothing — not even the base directory — yields a
  # name, leaving the caller on its own stem.
  private def cli_directory_binary_name(path : String) : String?
    segments = base_relative_path(path).split('/').reject(&.empty?)
    segments.pop? # the filename itself

    while name = segments.pop?
      return name unless CLI_LAYOUT_DIRS.includes?(name.downcase)
    end

    # Everything between the file and the scan base describes layout, so the
    # base directory itself is the best name available.
    base = configured_base_for(path)
    base = File.dirname(path) if base.empty?
    name = File.basename(File.expand_path(base))
    name.empty? ? nil : name
  end
end
