# LLM disk cache for AI responses
#
# Usage:
#   key = LLM::Cache.key(provider, model, kind, format, payload)
#   if cached = LLM::Cache.fetch(key)
#     use(cached)
#   else
#     response = call_llm(...)
#     LLM::Cache.store(key, response)
#   end

require "digest/sha256"
require "file_utils"
require "time"
require "../utils/home"
require "log"

module LLM
  module Cache
    # All cache entries are stored as `<sha256>.json` flat in
    # `cache_dir`. The bulk operations below (`clear`, `purge_older_than`,
    # `stats`) filter on this suffix so a stray `.lock` or user-dropped
    # file in the directory is left alone.
    CACHE_FILE_SUFFIX = ".json"

    # Infix `store` stamps onto its in-flight temp file (see `store`).
    # Kept as a constant so the writer and the sweepers below can't drift
    # apart: a stranded temp file whose name the sweepers don't recognize
    # is a file nothing can ever delete.
    CACHE_TMP_MARKER = ".tmp-"

    # True for a temp file stranded by a crash between `File.write` and
    # `File.rename`. These do *not* end in `.json`, so the bulk operations
    # used to skip them entirely — `clear` could not remove them and
    # `stats` did not count their bytes, leaving files that grew the cache
    # directory with no way to reclaim them from the CLI.
    def self.tmp_entry?(name : String) : Bool
      name.includes?("#{CACHE_FILE_SUFFIX}#{CACHE_TMP_MARKER}")
    end

    @@enabled = true

    def self.enabled? : Bool
      @@enabled && !disabled_by_env?
    end

    def self.enable : Nil
      @@enabled = true
    end

    def self.disable : Nil
      @@enabled = false
    end

    def self.disabled_by_env? : Bool
      return false unless ENV.has_key?("NOIR_CACHE_DISABLE")
      val = ENV["NOIR_CACHE_DISABLE"].strip.downcase
      val.in?(%w[1 true yes on])
    end

    def self.cache_dir : String
      File.join(Noir::Home.path, "cache", "ai")
    end

    # Build a deterministic cache key from inputs
    #
    # - provider: "openai", "ollama", url, etc.
    # - model: "gpt-4o", "llama3", etc.
    # - kind: logical operation e.g. "FILTER", "ANALYZE", "BUNDLE_ANALYZE"
    # - format: response_format string (e.g., "json" or JSON schema string)
    # - payload: variable content (file list, source code, bundle, etc.)
    #
    # Returns a hex-encoded SHA256 digest.
    def self.key(provider : String, model : String, kind : String, format : String, payload : String) : String
      digest = Digest::SHA256.new
      digest << provider << "|"
      digest << model << "|"
      digest << kind << "|"
      digest << format << "|"
      digest << payload
      digest.hexfinal
    end

    def self.path_for(key : String) : String
      File.join(cache_dir, "#{key}#{CACHE_FILE_SUFFIX}")
    end

    # 0700, and entries below are written 0600 (see `store`). A cache entry
    # is the model's answer about a specific chunk of the user's source, and
    # the prompt it answers is that source — private code, on a box that may
    # have other accounts. The default 0755/0644 published it to every local
    # user. `$NOIR_HOME/config.yaml` is already 0600 for the same reason.
    CACHE_DIR_PERMISSIONS  = 0o700
    CACHE_FILE_PERMISSIONS = 0o600

    def self.ensure_dir : Nil
      return if File.directory?(cache_dir)
      FileUtils.mkdir_p(cache_dir, CACHE_DIR_PERMISSIONS)
    end

    def self.fetch(key : String) : String?
      return unless enabled?
      path = path_for(key)
      return unless File.exists?(path)
      File.read(path)
    rescue e
      Log.debug { "Cache fetch failed for #{key}: #{e.message}" }
      nil
    end

    # Write atomically: a partially-written file from a crash mid-write
    # would parse as broken JSON on the next `fetch`, forcing a
    # spurious fresh API call. By writing to a tmp sibling and renaming
    # we either leave the previous (valid) entry in place or atomically
    # publish the new one.
    def self.store(key : String, content : String) : Bool
      return false unless enabled?
      ensure_dir
      final = path_for(key)
      tmp = "#{final}#{CACHE_TMP_MARKER}#{Process.pid}-#{Random::Secure.hex(4)}"
      # Permission set at create time, not chmod'd after: a reader racing the
      # write would otherwise get a window where the file is world-readable.
      File.write(tmp, content, perm: CACHE_FILE_PERMISSIONS)
      File.rename(tmp, final)
      true
    rescue e
      Log.debug { "Cache store failed for #{key}: #{e.message}" }
      begin
        File.delete(tmp) if tmp && File.exists?(tmp)
      rescue
        # best effort tmp cleanup
      end
      false
    end

    def self.delete(key : String) : Bool
      path = path_for(key)
      return false unless File.exists?(path)
      File.delete(path)
      true
    rescue e
      Log.debug { "Cache delete failed for #{key}: #{e.message}" }
      false
    end

    # Returned by bulk mutations so callers can surface both successful
    # deletes and per-file failures (the prior shape returned just an
    # Int32, hiding partial failures behind a single number that the
    # caller would print as if everything succeeded). `orphans` counts
    # reclaimed temp files separately so "removed N entries" keeps meaning
    # N real cached responses.
    record DeleteOutcome, deleted : Int32, failed : Int32, orphans : Int32 = 0 do
      def total
        deleted + failed
      end
    end

    def self.clear : DeleteOutcome
      delete_matching { |_| true }
    end

    def self.purge_older_than(days : Int32) : DeleteOutcome
      threshold = Time.utc - days.days
      delete_matching do |path|
        info = File.info(path)
        info.modification_time < threshold
      end
    end

    # Sweeps completed entries and stranded temp writes alike. A temp file
    # still being written by a concurrent process is only seconds old, so
    # `purge_older_than`'s mtime predicate never selects it; `clear` is
    # explicitly destructive and may take one, which the writer already
    # handles (its rename fails, `store` returns false, the next scan
    # re-requests).
    private def self.delete_matching(& : String -> Bool) : DeleteOutcome
      return DeleteOutcome.new(0, 0) unless File.directory?(cache_dir)
      deleted = 0
      failed = 0
      orphans = 0
      Dir.children(cache_dir).each do |entry|
        tmp = tmp_entry?(entry)
        next unless tmp || entry.ends_with?(CACHE_FILE_SUFFIX)
        fp = File.join(cache_dir, entry)
        next unless File.file?(fp)
        begin
          next unless yield(fp)
          File.delete(fp)
          tmp ? (orphans += 1) : (deleted += 1)
        rescue e
          Log.debug { "Cache delete failed for #{fp}: #{e.message}" }
          failed += 1
        end
      end
      DeleteOutcome.new(deleted, failed, orphans)
    end

    # `orphans`/`orphan_bytes` are tracked apart from `entries`/`bytes` so
    # `entries` keeps counting usable cached responses while the reported
    # footprint can still account for every byte the cache occupies.
    # Stranded temp files also stay out of `oldest`/`newest`, which
    # describe the age of the *usable* cache.
    record Stats,
      entries : Int32,
      bytes : Int64,
      oldest : Time?,
      newest : Time?,
      orphans : Int32 = 0,
      orphan_bytes : Int64 = 0

    def self.stats : Stats
      entries = 0
      bytes = 0_i64
      orphans = 0
      orphan_bytes = 0_i64
      oldest : Time? = nil
      newest : Time? = nil
      if File.directory?(cache_dir)
        Dir.children(cache_dir).each do |entry|
          tmp = tmp_entry?(entry)
          next unless tmp || entry.ends_with?(CACHE_FILE_SUFFIX)
          fp = File.join(cache_dir, entry)
          next unless File.file?(fp)
          begin
            info = File.info(fp)
            if tmp
              orphans += 1
              orphan_bytes += info.size.to_i64
              next
            end
            entries += 1
            bytes += info.size.to_i64
            mtime = info.modification_time
            oldest = oldest ? (mtime < oldest ? mtime : oldest) : mtime
            newest = newest ? (mtime > newest ? mtime : newest) : mtime
          rescue e
            Log.debug { "Cache stats: failed to read #{fp}: #{e.message}" }
          end
        end
      end
      Stats.new(
        entries: entries, bytes: bytes, oldest: oldest, newest: newest,
        orphans: orphans, orphan_bytes: orphan_bytes)
    end
  end
end
