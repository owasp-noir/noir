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
    # `stats`) filter on this suffix so a stray `.tmp`, `.lock`, or
    # user-dropped file in the directory is left alone.
    CACHE_FILE_SUFFIX = ".json"

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
      File.join(get_home, "cache", "ai")
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

    def self.ensure_dir : Nil
      return if File.directory?(cache_dir)
      FileUtils.mkdir_p(cache_dir)
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
      tmp = "#{final}.tmp-#{Process.pid}-#{Random::Secure.hex(4)}"
      File.write(tmp, content)
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
    # caller would print as if everything succeeded).
    record DeleteOutcome, deleted : Int32, failed : Int32 do
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

    private def self.delete_matching(& : String -> Bool) : DeleteOutcome
      return DeleteOutcome.new(0, 0) unless File.directory?(cache_dir)
      deleted = 0
      failed = 0
      Dir.children(cache_dir).each do |entry|
        next unless entry.ends_with?(CACHE_FILE_SUFFIX)
        fp = File.join(cache_dir, entry)
        next unless File.file?(fp)
        begin
          next unless yield(fp)
          File.delete(fp)
          deleted += 1
        rescue e
          Log.debug { "Cache delete failed for #{fp}: #{e.message}" }
          failed += 1
        end
      end
      DeleteOutcome.new(deleted, failed)
    end

    record Stats,
      entries : Int32,
      bytes : Int64,
      oldest : Time?,
      newest : Time?

    def self.stats : Stats
      entries = 0
      bytes = 0_i64
      oldest : Time? = nil
      newest : Time? = nil
      if File.directory?(cache_dir)
        Dir.children(cache_dir).each do |entry|
          next unless entry.ends_with?(CACHE_FILE_SUFFIX)
          fp = File.join(cache_dir, entry)
          next unless File.file?(fp)
          begin
            info = File.info(fp)
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
      Stats.new(entries: entries, bytes: bytes, oldest: oldest, newest: newest)
    end
  end
end
