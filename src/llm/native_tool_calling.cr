require "uri"

module LLM::NativeToolCalling
  DEFAULT_ALLOWLIST = ["openai", "xai", "github", "anthropic"]

  # Providers for which native tool-calling is actually wired up. Used to
  # validate --ai-native-tools-allowlist so a typo (e.g. `opena`) surfaces
  # a warning instead of silently never matching.
  KNOWN_PROVIDERS = ["openai", "xai", "github", "azure", "ollama", "vllm", "lmstudio", "anthropic", "google"]

  def self.known_provider?(provider : String) : Bool
    KNOWN_PROVIDERS.includes?(canonical_provider(provider))
  end

  def self.default_allowlist_csv : String
    DEFAULT_ALLOWLIST.join(",")
  end

  def self.canonical_provider(provider : String) : String
    p = provider.downcase.strip
    # The `gemini` preset shares the `google` token table and allowlist key.
    return "google" if p == "gemini"
    return p unless p.includes?("://") || p.includes?(".")

    # Match on the host, not on the whole URL. The path is chosen by whoever
    # runs the gateway, so `https://gw.internal/ollama/v1` used to canonicalize
    # to a provider the operator never named — the same substring bug that sent
    # such a URL to Ollama's native API in `AdapterFactory`. A host-less form
    # ("openai.com", "api.x.ai") still matches on the string itself.
    haystack = host_of(p) || p

    return "openai" if haystack.includes?("openai")
    return "xai" if haystack.includes?("x.ai") || haystack.includes?("xai")
    return "github" if haystack.includes?("github")
    return "azure" if haystack.includes?("azure")
    return "ollama" if haystack.includes?("ollama")
    return "vllm" if haystack.includes?("vllm")
    return "lmstudio" if haystack.includes?("lmstudio")
    return "openrouter" if haystack.includes?("openrouter")
    return "anthropic" if haystack.includes?("anthropic")
    return "google" if haystack.includes?("google") || haystack.includes?("gemini")
    return "cohere" if haystack.includes?("cohere")

    p
  end

  private def self.host_of(provider : String) : String?
    return unless provider.includes?("://")
    URI.parse(provider).host
  rescue URI::Error
    nil
  end

  def self.normalize_allowlist(allowlist : Array(String)? = nil) : Array(String)
    values = allowlist
    values = DEFAULT_ALLOWLIST if values.nil? || values.empty?

    values
      .map { |value| canonical_provider(value) }
      .reject(&.empty?)
      .uniq!
  end
end
