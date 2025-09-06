# noir/src/llm/adapter.cr
# Unified LLM adapter abstraction to normalize access across providers.
#
# This adapter wraps existing clients:
# - LLM::General (OpenAI-compatible chat APIs)
# - LLM::Ollama  (Ollama local API, with optional KV context reuse)
#
# Goals:
# - Single interface for sending messages or a raw prompt
# - Optional context-aware request for providers that support it
# - Easy future integration into analyzers to remove provider-specific branches

require "./general/client"
require "./ollama/ollama"

module LLM
  # A normalized adapter interface for LLM clients.
  #
  # Implementations should return a String response (JSON text after any provider-specific cleanup).
  module Adapter
    alias Messages = Array(Hash(String, String))

    # Send chat-style messages (system/user) and get a response as a String.
    abstract def request_messages(messages : Messages, format : String = "json") : String

    # Send a single prompt and get a response as a String.
    abstract def request(prompt : String, format : String = "json") : String

    # Whether this adapter supports server-side KV context reuse across calls.
    def supports_context? : Bool
      false
    end

    # Context-aware request. Adapters that support provider-side context can reuse it using a cache_key.
    # Default implementation falls back to request_messages without context reuse.
    def request_with_context(system : String?, user : String, format : String = "json", cache_key : String? = nil) : String
      msgs = [] of Hash(String, String)
      if system && !system.empty?
        msgs << {"role" => "system", "content" => system}
      end
      msgs << {"role" => "user", "content" => user}
      request_messages(msgs, format)
    end
  end

  # Adapter for OpenAI-compatible chat APIs (LLM::General).
  class GeneralAdapter
    include Adapter

    getter client : LLM::General

    def initialize(@client : LLM::General)
    end

    def request_messages(messages : Messages, format : String = "json") : String
      client.request_messages(messages, format)
    end

    def request(prompt : String, format : String = "json") : String
      client.request(prompt, format)
    end
  end

  # Adapter for Ollama (LLM::Ollama) with optional context reuse.
  class OllamaAdapter
    include Adapter

    getter client : LLM::Ollama

    def initialize(@client : LLM::Ollama)
    end

    def supports_context? : Bool
      true
    end

    # For Ollama, messages are flattened to "system\n\nuser" when context reuse isn't explicitly used.
    def request_messages(messages : Messages, format : String = "json") : String
      system_msg, user_payload = flatten_messages(messages)
      # Use context-aware method without a cache key to preserve consistent behavior.
      client.request_with_context(system_msg, user_payload, format, nil)
    end

    def request(prompt : String, format : String = "json") : String
      client.request(prompt, format)
    end

    # Pass-through to the underlying context-aware API for maximum efficiency.
    def request_with_context(system : String?, user : String, format : String = "json", cache_key : String? = nil) : String
      client.request_with_context(system, user, format, cache_key)
    end

    private def flatten_messages(messages : Messages) : {String?, String}
      systems = [] of String
      users = [] of String
      messages.each do |m|
        role = m["role"]?
        content = m["content"]?
        next unless role && content
        case role
        when "system" then systems << content
        when "user"   then users << content
        else
          # ignore assistant/tool/etc for current use case
        end
      end
      sys = systems.empty? ? nil : systems.join("\n\n")
      usr = users.join("\n\n")
      {sys, usr}
    end
  end

  # Simple factory for creating adapters.
  #
  # - If provider indicates Ollama (contains "ollama"), returns OllamaAdapter
  # - Otherwise returns GeneralAdapter
  #
  # Note: This factory does not guess default URLs beyond provider tokens.
  #       Callers should pass proper values depending on their configuration.
  class AdapterFactory
    def self.for(provider : String, model : String, api_key : String? = nil) : Adapter
      prov = provider.downcase
      if prov.includes?("ollama")
        # Heuristic: If provider looks like a URL, pass as-is. Otherwise use a common default base.
        url = provider.includes?("://") ? provider : "http://localhost:11434"
        OllamaAdapter.new(LLM::Ollama.new(url, model))
      else
        # For OpenAI-compatible servers, LLM::General handles mapping known tokens (e.g., "openai") to URLs.
        GeneralAdapter.new(LLM::General.new(provider, model, api_key))
      end
    end
  end
end
