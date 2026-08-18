# Unified LLM adapter abstraction to normalize access across providers.
#
# Supports:
# - LLM::General (OpenAI-compatible chat APIs)
# - LLM::Ollama (Ollama local API with optional KV context reuse)

require "uri"
require "./general/client"
require "./ollama/ollama"
require "./acp/client"
require "./native_tool_calling"

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

    # Whether this adapter can leverage provider-native tool-calling.
    def supports_native_tool_calling? : Bool
      false
    end

    # Request next step using provider-native tool definitions.
    # Implementations that do not support this can fallback to regular JSON-mode requests.
    def request_messages_with_tools(messages : Messages, _tools : String) : String
      request_messages(messages, "json")
    end

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

    # Optional cleanup hook for adapters that manage external resources.
    def close : Nil
    end
  end

  # Adapter for OpenAI-compatible chat APIs (LLM::General).
  class GeneralAdapter
    include Adapter

    getter client : LLM::General

    def initialize(@client : LLM::General, @native_tool_calling_enabled : Bool = true)
    end

    def request_messages(messages : Messages, format : String = "json") : String
      client.request_messages(messages, format)
    end

    def request(prompt : String, format : String = "json") : String
      client.request(prompt, format)
    end

    def supports_native_tool_calling? : Bool
      @native_tool_calling_enabled
    end

    def request_messages_with_tools(messages : Messages, tools : String) : String
      client.request_messages_with_tools(messages, tools)
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

    # Promoted to a class-level pure function so the flattening rule
    # (system messages joined with \n\n, non-system/non-user roles
    # dropped, nil system when no system messages were present) is
    # unit-testable without standing up a real Ollama client.
    def self.flatten_messages(messages : Messages) : {String?, String}
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

    private def flatten_messages(messages : Messages) : {String?, String}
      self.class.flatten_messages(messages)
    end
  end

  # Adapter for ACP-based agents (codex, gemini, claude, etc.).
  class ACPAdapter
    include Adapter

    getter client : LLM::ACPClient

    def initialize(@client : LLM::ACPClient)
    end

    def request_messages(messages : Messages, format : String = "json") : String
      client.request_messages(messages, format)
    end

    def request(prompt : String, format : String = "json") : String
      client.request(prompt, format)
    end

    def close : Nil
      client.close
    end
  end

  # Factory for creating LLM adapters based on provider configuration.
  class AdapterFactory
    def self.native_tool_calling_enabled_for_provider?(provider : String, allowlist : Array(String)? = nil) : Bool
      active_allowlist = LLM::NativeToolCalling.normalize_allowlist(allowlist)
      active_allowlist.includes?(LLM::NativeToolCalling.canonical_provider(provider))
    end

    # Ollama's native API (`POST /api/generate`) is a different protocol and a
    # different body shape from the OpenAI-compatible `/v1/chat/completions`
    # every other provider speaks, so this decision has to be precise.
    #
    # It used to be `provider.downcase.includes?("ollama")` tested against the
    # *whole* provider string. A path segment is chosen by whoever runs the
    # gateway, so an OpenAI-compatible endpoint mounted at
    # `http://gw.example/ollama/v1` was handed the wrong API — and, because
    # the same full string is used as the base URL, the request went to
    # `http://gw.example/ollama/v1/api/generate`. The 404 came back as an
    # empty result rather than an error.
    #
    # Only the exact alias and the *host* decide now. A host named `ollama`
    # that is explicitly serving the compatibility path is still an
    # OpenAI-compatible endpoint.
    def self.ollama_native?(provider : String) : Bool
      prov = provider.strip.downcase
      return true if prov == "ollama"
      return false unless prov.includes?("://")

      uri = URI.parse(prov)
      host = uri.host
      return false if host.nil? || !host.includes?("ollama")

      !uri.path.to_s.chomp("/").ends_with?("/chat/completions")
    rescue URI::Error
      false
    end

    # The native API lives at the server root. The CLI's own help prints
    # `ollama -> http://localhost:11434/v1`, and that `/v1` is the
    # OpenAI-compatible mount: appending `/api/generate` to it yields a 404,
    # so it is dropped before `LLM::Ollama` builds the endpoint URL.
    def self.ollama_base_url(provider : String) : String
      prov = provider.strip
      return "http://localhost:11434" unless prov.includes?("://")
      prov.chomp("/").rchop("/v1").chomp("/")
    end

    def self.for(
      provider : String,
      model : String,
      api_key : String? = nil,
      event_sink : Proc(String, Nil)? = nil,
      native_tool_calling_allowlist : Array(String)? = nil,
    ) : Adapter
      prov = provider.downcase
      if LLM::ACPClient.acp_provider?(prov)
        acp_model = LLM::ACPClient.default_model(provider, model)
        ACPAdapter.new(LLM::ACPClient.new(provider, acp_model, event_sink))
      elsif ollama_native?(prov)
        OllamaAdapter.new(LLM::Ollama.new(ollama_base_url(provider), model))
      else
        native_tool_calling = native_tool_calling_enabled_for_provider?(provider, native_tool_calling_allowlist)
        GeneralAdapter.new(LLM::General.new(provider, model, api_key), native_tool_calling)
      end
    end
  end
end
