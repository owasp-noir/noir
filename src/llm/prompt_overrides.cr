require "./prompt"

module LLM::PromptOverrides
  class_property filter_prompt : String = LLM::FILTER_PROMPT
  class_property analyze_prompt : String = LLM::ANALYZE_PROMPT
  class_property bundle_analyze_prompt : String = LLM::BUNDLE_ANALYZE_PROMPT
  class_property llm_optimize_prompt : String = <<-PROMPT
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
