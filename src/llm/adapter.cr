# Unified LLM adapter abstraction to normalize access across providers.
#
# Supports:
# - LLM::General (OpenAI-compatible chat APIs)
# - LLM::Ollama (Ollama local API with optional KV context reuse)

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

    def request_messages(messages : Messages, format : String = "json") : String
      system_msg, user_payload = flatten_messages(messages)
      client.request_with_context(system_msg, user_payload, format, nil)
    end

    def request(prompt : String, format : String = "json") : String
      client.request(prompt, format)
    end

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
        end
      end
      sys = systems.empty? ? nil : systems.join("\n\n")
      usr = users.join("\n\n")
      {sys, usr}
    end
  end

  # Factory for creating LLM adapters based on provider configuration.
  class AdapterFactory
    def self.for(provider : String, model : String, api_key : String? = nil) : Adapter
      prov = provider.downcase
      if prov.includes?("ollama")
        url = provider.includes?("://") ? provider : "http://localhost:11434"
        OllamaAdapter.new(LLM::Ollama.new(url, model))
      else
        GeneralAdapter.new(LLM::General.new(provider, model, api_key))
      end
    end
  end
end
