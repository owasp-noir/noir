require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  # Supabase exposes every table in an exposed schema over PostgREST at
  # `/rest/v1/<table>`, so the migration SQL *is* the API definition.
  #
  # `.sql` is a file class no other Noir detector opens, and `CREATE
  # TABLE` is the most universal statement in SQL — a Rails
  # `db/structure.sql`, a Flyway `V1__init.sql` or any schema dump would
  # match on content alone. The gate is therefore path-first, in two
  # tiers:
  #
  #   * under `supabase/`  -> `create table` is enough
  #   * under `migrations/` -> additionally requires an RLS/Supabase
  #     fingerprint, because that directory name belongs to every
  #     migration tool there is
  #
  # Bare PostgREST (a Postgres schema with no `supabase/` directory) is
  # deliberately not supported: PostgREST reads the live database and
  # adds no syntax of its own, so nothing in the file distinguishes a
  # schema served by PostgREST from any other schema.
  class Supabase < Detector
    # `alter table` counts too: a migration that only adds a column is
    # still part of the schema, and dropping those would leave the
    # emitted params stuck at whatever the first migration declared.
    DDL_MARKER = /\bcreate\s+(?:global\s+|local\s+|temp(?:orary)?\s+|unlogged\s+)*table\b|\balter\s+table\b/i

    # Constructs that only appear in a Supabase/PostgREST-managed schema.
    SUPABASE_FINGERPRINT = /\bauth\.uid\s*\(|\benable\s+row\s+level\s+security\b|\bcreate\s+policy\b|\bstorage\.objects\b|\bauth\.users\b|\bpgrst\b|\bsupabase\b/i

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      path = normalize(filename)

      if File.basename(path) == "config.toml"
        CodeLocator.instance.push("supabase-config", filename)
        return true
      end

      return false unless file_contents.matches?(DDL_MARKER)

      unless supabase_directory?(path)
        return false unless file_contents.matches?(SUPABASE_FINGERPRINT)
      end

      CodeLocator.instance.push("supabase-migration", filename)
      true
    end

    # Memo safety: `applicable?` consults the path
    # (supabase/ and migrations/ gates), not just the basename.
    def path_sensitive? : Bool
      true
    end

    def applicable?(filename : String) : Bool
      path = normalize(filename)

      return true if File.basename(path) == "config.toml" && supabase_directory?(path)
      return false unless path.ends_with?(".sql")

      supabase_directory?(path) || path.includes?("/migrations/") || path.starts_with?("migrations/")
    end

    def set_name
      @name = "supabase"
    end

    # Registers every migration path in `CodeLocator`.
    def idempotent? : Bool
      false
    end

    private def supabase_directory?(path : String) : Bool
      scoped = strip_base(path)
      scoped.includes?("/supabase/") || scoped.starts_with?("supabase/")
    end

    # The gate is evaluated against the path *relative to the scan base*.
    # Otherwise wherever the project happens to sit on disk leaks into
    # detection — a checkout at `/src/supabase/myapp` would make every
    # `.sql` under it look like a Supabase migration.
    private def strip_base(path : String) : String
      @base_paths.each do |base|
        normalized = normalize(base).rstrip('/')
        next if normalized.empty?
        prefix = "#{normalized}/"
        return path[prefix.size..] if path.starts_with?(prefix)
      end
      path
    end

    private def normalize(filename : String) : String
      filename.includes?('\\') ? filename.gsub('\\', '/') : filename
    end
  end
end
