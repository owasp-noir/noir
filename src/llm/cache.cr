# frozen_string_literal: true
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

module LLM
  module Cache
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
      data = String.build do |io|
        io << provider << '|'
        io << model << '|'
        io << kind << '|'
        io << format << '|'
        io << payload
      end
      Digest::SHA256.hexdigest(data)
    end

    # Get the file system path for a given key
    def self.path_for(key : String) : String
      File.join(cache_dir, "#{key}.json")
    end

    # Ensure the cache directory exists
    def self.ensure_dir : Nil
      return if File.directory?(cache_dir)
      FileUtils.mkdir_p(cache_dir)
    end

    # Fetch cached content by key (returns nil if not present)
    def self.fetch(key : String) : String?
      path = path_for(key)
      return nil unless File.exists?(path)
      File.read(path)
    rescue
      nil
    end

    # Store content for a key. Returns true on success.
    def self.store(key : String, content : String) : Bool
      ensure_dir
      File.write(path_for(key), content)
      true
    rescue
      false
    end

    # Remove a cached entry by key. Returns true if a file was removed.
    def self.delete(key : String) : Bool
      path = path_for(key)
      return false unless File.exists?(path)
      File.delete(path)
      true
    rescue
      false
    end

    # Clear all cache entries. Returns the number of deleted files.
    def self.clear : Int32
      return 0 unless File.directory?(cache_dir)
      count = 0
      Dir.children(cache_dir).each do |entry|
        fp = File.join(cache_dir, entry)
        next unless File.file?(fp)
        begin
          File.delete(fp)
          count += 1
        rescue
          # ignore failures and continue
        end
      end
      count
    end

    # Purge entries older than the specified number of days.
    # Returns the number of deleted files.
    def self.purge_older_than(days : Int32) : Int32
      return 0 unless File.directory?(cache_dir)
      threshold = Time.utc - days.days
      count = 0
      Dir.children(cache_dir).each do |entry|
        fp = File.join(cache_dir, entry)
        next unless File.file?(fp)
        begin
          info = File.info(fp)
          if info.modification_time < threshold
            File.delete(fp)
            count += 1
          end
        rescue
          # ignore and continue
        end
      end
      count
    end

    # Returns simple statistics for the cache directory:
    # - "entries": number of files
    # - "bytes": total size in bytes
    def self.stats : Hash(String, Int64)
      entries = 0_i64
      bytes = 0_i64
      if File.directory?(cache_dir)
        Dir.children(cache_dir).each do |entry|
          fp = File.join(cache_dir, entry)
          next unless File.file?(fp)
          begin
            entries += 1
            bytes += File.size(fp)
          rescue
            # ignore files that disappear mid-scan
          end
        end
      end
      {"entries" => entries, "bytes" => bytes}
    end
  end
end
