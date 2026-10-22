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
require "../models/logger"
require "./sampling"

module LLM
  module Cache
    # Where the swallowed cache failures below are reported.
    #
    # They used to go to Crystal's global `Log` at debug level, which was
    # wrong twice over: that logger's default backend writes to **STDOUT**,
    # the stream carrying the `-f json` / `-f sarif` report, and nothing in
    # Noir ever lowers its `Info` threshold, so the messages could not
    # surface at all. A diagnostic that is simultaneously invisible and
    # aimed at the report stream is the worst of both.
    #
    # `NoirLogger` (STDERR, gated on `--debug`) is where every other Noir
    # diagnostic goes. Nil until a run installs one, so a library caller
    # constructing no logger stays silent exactly as before.
    class_setter logger : NoirLogger? = nil

    private def self.debug(message : String) : Nil
      @@logger.try &.debug(message)
    end

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
    @@hits = Atomic(Int32).new(0)

    # Responses served from disk this run, for the end-of-run usage line.
    def self.hits : Int32
      @@hits.get
    end

    def self.enabled? : Bool
      @@enabled && !disabled_by_env?
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

    # The prompts themselves are part of every key. Bump this when a change
    # outside them (adapter-side wrapping, how a reply is read) should stop
    # older cached replies from being replayed.
    KEY_VERSION = "2"

    # Build a deterministic cache key from inputs
    #
    # - provider: "openai", "ollama", url, etc.
    # - model: "gpt-4o", "llama3", etc.
    # - kind: logical operation e.g. "FILTER", "ANALYZE", "BUNDLE_ANALYZE"
    # - format: response_format string (e.g., "json" or JSON schema string)
    # - payload: variable content (file list, source code, bundle, etc.)
    #
    # The sampling settings are folded in too, so a reply sampled at another
    # temperature or seed is not replayed.
    #
    # Returns a hex-encoded SHA256 digest.
    def self.key(provider : String, model : String, kind : String, format : String, payload : String) : String
      digest = Digest::SHA256.new
      sampling = "#{Sampling.temperature}|#{Sampling.seed}"
      # Length prefixes keep fields distinct when a model, schema, or source
      # payload itself contains the separator used by the old encoding.
      {KEY_VERSION, provider, model, kind, format, payload, sampling}.each do |part|
        digest << part.bytesize.to_s << ":" << part
      end
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
      FileUtils.mkdir_p(cache_dir, CACHE_DIR_PERMISSIONS)
    end

    def self.fetch(key : String) : String?
      return unless enabled?
      path = path_for(key)
      return unless File.exists?(path)
      content = File.read(path)
      @@hits.add(1)
      content
    rescue e
      debug("Cache fetch failed for #{key}: #{e.message}")
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
      debug("Cache store failed for #{key}: #{e.message}")
      begin
        File.delete(tmp) if tmp && File.exists?(tmp)
      rescue
        # best effort tmp cleanup
      end
      false
    end

    # Returned by bulk mutations so callers can surface both successful
    # deletes and per-file failures (the prior shape returned just an
    # Int32, hiding partial failures behind a single number that the
    # caller would print as if everything succeeded). `orphans` counts
    # reclaimed temp files separately so "removed N entries" keeps meaning
    # N real cached responses.
    record DeleteOutcome, deleted : Int32, failed : Int32, orphans : Int32 = 0

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
      deleted = 0
      failed = 0
      orphans = 0
      each_entry do |fp, tmp|
        next unless yield(fp)
        File.delete(fp)
        tmp ? (orphans += 1) : (deleted += 1)
      rescue e
        debug("Cache delete failed for #{fp}: #{e.message}")
        failed += 1
      end
      DeleteOutcome.new(deleted, failed, orphans)
    end

    # Every cache file — completed entries and stranded temp writes (`tmp`)
    # — skipping anything else a user dropped into the directory.
    private def self.each_entry(& : String, Bool ->) : Nil
      return unless File.directory?(cache_dir)
      Dir.children(cache_dir).each do |entry|
        tmp = tmp_entry?(entry)
        next unless tmp || entry.ends_with?(CACHE_FILE_SUFFIX)
        fp = File.join(cache_dir, entry)
        yield fp, tmp if File.file?(fp)
      end
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
      each_entry do |fp, tmp|
        info = File.info(fp)
        if tmp
          orphans += 1
          orphan_bytes += info.size.to_i64
          next
        end
        entries += 1
        bytes += info.size.to_i64
        mtime = info.modification_time
        oldest = mtime if oldest.nil? || mtime < oldest
        newest = mtime if newest.nil? || mtime > newest
      rescue e
        debug("Cache stats: failed to read #{fp}: #{e.message}")
      end
      Stats.new(
        entries: entries, bytes: bytes, oldest: oldest, newest: newest,
        orphans: orphans, orphan_bytes: orphan_bytes)
    end
  end
end
