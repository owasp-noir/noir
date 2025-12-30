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
      val = ENV["NOIR_CACHE_DISABLE"]
      ["1", "true", "yes", "on"].includes?(val.downcase)
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
      data = String.build do |io|
        io << provider << '|'
        io << model << '|'
        io << kind << '|'
        io << format << '|'
        io << payload
      end
      Digest::SHA256.hexdigest(data)
    end

    def self.path_for(key : String) : String
      File.join(cache_dir, "#{key}.json")
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
    rescue
      nil
    end

    def self.store(key : String, content : String) : Bool
      return false unless enabled?
      ensure_dir
      File.write(path_for(key), content)
      true
    rescue
      false
    end

    def self.delete(key : String) : Bool
      path = path_for(key)
      return false unless File.exists?(path)
      File.delete(path)
      true
    rescue
      false
    end

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
        end
      end
      count
    end

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
        end
      end
      count
    end

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
          end
        end
      end
      {"entries" => entries, "bytes" => bytes}
    end
  end
end
