require "./prompt"

module LLM::PromptOverrides
  # Class variables to store prompt overrides
  @@filter_prompt_override : String?
  @@analyze_prompt_override : String?
  @@bundle_analyze_prompt_override : String?
  @@llm_optimize_prompt_override : String?

  # Setters for prompt overrides
  def self.filter_prompt=(value : String)
    @@filter_prompt_override = value
  end

  def self.analyze_prompt=(value : String)
    @@analyze_prompt_override = value
  end

  def self.bundle_analyze_prompt=(value : String)
    @@bundle_analyze_prompt_override = value
  end

  def self.llm_optimize_prompt=(value : String)
    @@llm_optimize_prompt_override = value
  end

  # Getters that return override or default
  def self.filter_prompt
    @@filter_prompt_override || LLM::FILTER_PROMPT
  end

  def self.analyze_prompt
    @@analyze_prompt_override || LLM::ANALYZE_PROMPT
  end

  def self.bundle_analyze_prompt
    @@bundle_analyze_prompt_override || LLM::BUNDLE_ANALYZE_PROMPT
  end

  def self.llm_optimize_prompt
    @@llm_optimize_prompt_override || get_default_llm_optimize_prompt
  end

  # Default LLM_OPTIMIZE_PROMPT value from the optimizer module
  private def self.get_default_llm_optimize_prompt
    <<-PROMPT
    Analyze the provided endpoint and optimize it for better structure, naming conventions, and parameter handling.

    Focus on:
    - Normalizing unusual URL patterns
    - Improving parameter naming conventions
    - Standardizing path structures
    - Removing redundant or confusing elements

    Guidelines:
    - Keep the core functionality and meaning intact
    - Use RESTful conventions where appropriate
    - Ensure parameter types are accurate
    - Maintain endpoint uniqueness
    - Do not include explanations or comments
    - Output only the JSON result according to the schema
    PROMPT
  end
end
