require "../../models/analyzer"

module Analyzer::Perl
  abstract class PerlEngine < Analyzer
    def analyze
      parallel_file_scan do |path|
        result.concat(analyze_file(path))
      end
      result
    end

    abstract def analyze_file(path : String) : Array(Endpoint)

    # No extension filter at the engine layer: Perl ships in `.pl`, `.pm`,
    # `.psgi`, and `.t` files, so each analyzer filters inside `analyze_file`.
    protected def parallel_file_scan(&block : String -> Nil) : Nil
      begin
        parallel_analyze(all_files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)

          begin
            block.call(path)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
          end
        end
      rescue e
        logger.debug e
      end
    end

    # Perl test files live in `.t` scripts or under a `/t/` directory.
    protected def perl_test_path?(path : String, ext : String) : Bool
      return true if ext == ".t"
      return true if path.includes?("/t/")
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
