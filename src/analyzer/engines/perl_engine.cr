require "../../models/analyzer"
require "../../utils/path_scope"

require "./file_scan_engine"

module Analyzer::Perl
  abstract class PerlEngine < FileScanEngine
    # Perl ships in `.pl`, `.pm`, `.psgi`, and `.t`. Pull those from the
    # extension index instead of walking the whole monorepo `file_map`.
    # Adapters still re-filter inside `analyze_file` for framework-specific
    # rules (e.g. skipping `.t` tests). Paths are detector-registered
    # regular files — no per-path `File.exists?` / `File.directory?`.
    PERL_SOURCE_EXTENSIONS = [".pl", ".pm", ".psgi", ".t"]

    # Perl dependency manifests. `cpanfile` and `Makefile.PL` are the common
    # pair; `Build.PL`, `dist.ini` and the generated `META.*` cover the
    # Module::Build / Dist::Zilla layouts.
    PERL_MANIFEST_BASENAMES = %w[cpanfile cpanfile.snapshot Makefile.PL Build.PL dist.ini META.json META.yml META.yaml]

    protected def scan_target_files : Array(String)
      get_files_by_extensions(PERL_SOURCE_EXTENSIONS)
    end

    # The CPAN distributions that identify this analyzer's framework. An
    # analyzer that declares one is only shown files from a project whose
    # dependency manifest requires it. Without that gate every Perl analyzer
    # sees every `.pm`/`.pl`/`.psgi` in the scan, so a repo holding a Dancer2
    # app next to a Mojolicious one has each analyzer reading the other's
    # files. Default is empty, meaning no gate — mirrors `CrystalEngine`'s
    # `shard_dependencies` and `RustEngine`'s `crate_dependencies`.
    protected def cpan_dependencies : Array(String)
      [] of String
    end

    protected def scan_accepts?(path : String) : Bool
      path_under_perl_roots?(path)
    end

    # A file belongs to this analyzer's framework when it sits under a
    # project whose manifest requires one of `cpan_dependencies` — or under
    # no manifested project at all. That second clause matters for Perl in a
    # way it doesn't for Crystal or Rust: a great many Perl projects are a
    # bare script directory with no `cpanfile`, and dropping them the moment
    # some *other* directory in the scan happens to carry a manifest would
    # cost real routes.
    protected def path_under_perl_roots?(path : String) : Bool
      return true if cpan_dependencies.empty?

      framework_roots = perl_framework_roots
      expanded = File.expand_path(path)
      return true if framework_roots.any? { |root| Noir::PathScope.under_normalized_root?(expanded, root) }

      perl_manifest_roots.none? { |root| Noir::PathScope.under_normalized_root?(expanded, root) }
    end

    @perl_manifest_roots : Array(String)?
    @perl_framework_roots : Array(String)?

    # Directories holding any Perl dependency manifest.
    private def perl_manifest_roots : Array(String)
      @perl_manifest_roots ||= collect_manifest_roots { true }
    end

    # Directories holding a manifest that requires one of `cpan_dependencies`.
    private def perl_framework_roots : Array(String)
      @perl_framework_roots ||= begin
        dependencies = cpan_dependencies
        if dependencies.empty?
          [] of String
        else
          collect_manifest_roots { |content| dependencies.any? { |name| content.includes?(name) } }
        end
      end
    end

    private def collect_manifest_roots(&accept : String -> Bool) : Array(String)
      roots = [] of String
      PERL_MANIFEST_BASENAMES.each do |basename|
        get_files_by_basename(basename).each do |file|
          begin
            content = read_file_content(file)
          rescue e
            logger.debug "perl manifest #{file}: #{e}"
            next
          end
          next unless accept.call(content)
          root = Noir::PathScope.normalize_root(File.dirname(file))
          roots << root unless roots.includes?(root)
        end
      end
      roots
    end

    # Perl test files live in `.t` scripts or under a `/t/` directory.
    # Scan-base-relative, never absolute. `t` is a single character, so
    # matching the absolute path was catastrophic in practice: any
    # ancestor directory literally named `t` — and every checkout under
    # one — lost its whole endpoint set (the Perl fixture tree went from
    # 109 endpoints to 0).
    protected def perl_test_path?(path : String, ext : String) : Bool
      return true if ext == ".t"
      return true if base_relative_path(path).includes?("/t/")
      false
    end

    # Blank out POD blocks (`=foo ... =cut`) and everything after
    # `__END__` / `__DATA__`, preserving line alignment so downstream
    # line/brace bookkeeping stays correct. Analyzers with bespoke
    # sanitization may override this.
    protected def sanitize_perl_lines(lines : Array(String)) : Array(String)
      in_pod = false
      ended = false
      lines.map do |line|
        stripped = line.lstrip
        if ended
          ""
        elsif stripped.starts_with?("__END__") || stripped.starts_with?("__DATA__")
          ended = true
          ""
        elsif in_pod
          if stripped.starts_with?("=cut")
            in_pod = false
          end
          ""
        elsif stripped.size >= 2 && stripped[0] == '=' && stripped[1].ascii_letter?
          # POD directives: =head1, =head2, =item, =over, =pod, =for, =begin, =encoding ...
          in_pod = true
          ""
        else
          line
        end
      end
    end
  end
end
