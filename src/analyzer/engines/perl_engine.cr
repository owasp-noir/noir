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
      expanded = Noir::PathScope.expand(path)
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
      PerlEngine.sanitize_lines(lines)
    end

    def self.sanitize_lines(lines : Array(String)) : Array(String)
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

    # `line` cut at its `#` comment. A `#` is code inside a quoted string,
    # in `$#array` / `$#{...}`, and anywhere inside a quote-like operator or
    # regex: `s#a#b#`, `tr###`, `m#x#`, `qr#x#`, `q{#}`, `/[^#]/` are read
    # through their full delimiter count before comments are looked for.
    def self.strip_line_comment(line : String) : String
      return line unless line.byte_index('#'.ord)

      size = line.bytesize
      i = 0
      while i < size
        byte = line.byte_at(i)
        if byte == '"'.ord || byte == '\''.ord
          i = skip_perl_delimited(line, i + 1, byte, 0_u8, 1)
          next
        elsif byte == '/'.ord && perl_regex_start?(line, i)
          i = skip_perl_delimited(line, i + 1, byte, 0_u8, 1)
          next
        elsif perl_word_start?(line, i)
          k = i
          while k < size && (line.byte_at(k).unsafe_chr.ascii_alphanumeric? || line.byte_at(k) == '_'.ord)
            k += 1
          end
          if (parts = PERL_QUOTE_LIKE_PARTS[line.byte_slice(i, k - i)]?) && (d = perl_quote_delimiter(line, k))
            delimiter = line.byte_at(d)
            closer = PERL_DELIMITER_CLOSERS[delimiter]? || delimiter
            i = skip_perl_delimited(line, d + 1, closer, closer == delimiter ? 0_u8 : delimiter, parts)
          else
            i = k
          end
          next
        elsif byte == '#'.ord && !(i > 0 && line.byte_at(i - 1) == '$'.ord)
          return line.byte_slice(0, i)
        end
        i += 1
      end
      line
    end

    # Quote-like operators and how many delimited parts follow them.
    PERL_QUOTE_LIKE_PARTS = {
      "q" => 1, "qq" => 1, "qw" => 1, "qr" => 1, "qx" => 1, "m" => 1,
      "s" => 2, "tr" => 2, "y" => 2,
    }
    PERL_DELIMITER_CLOSERS = {'('.ord.to_u8 => ')'.ord.to_u8, '['.ord.to_u8 => ']'.ord.to_u8,
                              '{'.ord.to_u8 => '}'.ord.to_u8, '<'.ord.to_u8 => '>'.ord.to_u8}

    # A bareword, not part of a name, a variable (`$s`, `@m`) or a method
    # (`->s(...)`, `Foo::q`).
    private def self.perl_word_start?(line : String, index : Int32) : Bool
      return false unless line.byte_at(index).unsafe_chr.ascii_letter?
      return true if index == 0
      prev = line.byte_at(index - 1).unsafe_chr
      return false if prev.ascii_alphanumeric? || {'_', '$', '@', '%', '&', ':', '>'}.includes?(prev)
      true
    end

    # Offset of the opening delimiter after a quote-like word ending at
    # `index`, or nil when the word is a plain name (`s => 1`, `y;`). A `#`
    # delimiter must follow immediately; brackets and `/` may follow spaces.
    private def self.perl_quote_delimiter(line : String, index : Int32) : Int32?
      return if index >= line.bytesize
      char = line.byte_at(index).unsafe_chr
      if char.ascii_whitespace?
        k = index
        while k < line.bytesize && line.byte_at(k).unsafe_chr.ascii_whitespace?
          k += 1
        end
        return if k >= line.bytesize
        return {'(', '[', '{', '<', '/'}.includes?(line.byte_at(k).unsafe_chr) ? k : nil
      end
      return if char.ascii_alphanumeric? || line.byte_at(index) >= 0x80 ||
                {'_', '=', ',', ';', ')', ']', '}', '>'}.includes?(char)
      index
    end

    # A `/` opens a match when the previous non-blank byte cannot end an
    # operand (`=~ /re/`, `(/re/`, `split /,/` is left as division).
    private def self.perl_regex_start?(line : String, index : Int32) : Bool
      k = index - 1
      while k >= 0 && line.byte_at(k).unsafe_chr.ascii_whitespace?
        k -= 1
      end
      k < 0 || {'(', ',', '=', '~', '!', ';', '{', '[', '|', '&', '?', ':'}.includes?(line.byte_at(k).unsafe_chr)
    end

    # Offset just past `parts` delimited sections starting at `index` (just
    # inside the first one). Bracket delimiters nest; for `s{a}{b}` the next
    # section opens with its own bracket after optional blanks, while
    # `s#a#b#` reuses the closer as the next opener. An unclosed section runs
    # to the end of the line.
    private def self.skip_perl_delimited(line : String, index : Int32, closer : UInt8, opener : UInt8, parts : Int32) : Int32
      size = line.bytesize
      depth = 0
      i = index
      while i < size
        byte = line.byte_at(i)
        if byte == '\\'.ord
          i += 2
          next
        elsif opener != 0 && byte == opener
          depth += 1
        elsif byte == closer
          if depth > 0
            depth -= 1
          else
            parts -= 1
            return i + 1 if parts == 0
            if opener != 0
              k = i + 1
              while k < size && line.byte_at(k).unsafe_chr.ascii_whitespace?
                k += 1
              end
              return k if k >= size
              opener = line.byte_at(k)
              closer = PERL_DELIMITER_CLOSERS[opener]? || opener
              opener = 0_u8 if closer == opener
              i = k
            end
          end
        end
        i += 1
      end
      size
    end
  end
end
