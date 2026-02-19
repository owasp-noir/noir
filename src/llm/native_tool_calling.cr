module LLM::NativeToolCalling
  DEFAULT_ALLOWLIST = ["openai", "xai", "github"]

  def self.default_allowlist : Array(String)
    DEFAULT_ALLOWLIST.clone
  end

  def self.default_allowlist_csv : String
    DEFAULT_ALLOWLIST.join(",")
  end

  def self.canonical_provider(provider : String) : String
    p = provider.downcase.strip

    if p.includes?("://") || p.includes?(".")
      return "openai" if p.includes?("openai")
      return "xai" if p.includes?("x.ai") || p.includes?("xai")
      return "github" if p.includes?("github")
      return "azure" if p.includes?("azure")
      return "ollama" if p.includes?("ollama")
      return "vllm" if p.includes?("vllm")
      return "lmstudio" if p.includes?("lmstudio")
    end

    p
  end

  def self.normalize_allowlist(allowlist : Array(String)? = nil) : Array(String)
    values = allowlist
    values = default_allowlist if values.nil? || values.empty?

    values
      .map { |value| canonical_provider(value) }
      .reject(&.empty?)
      .uniq
  end
end
