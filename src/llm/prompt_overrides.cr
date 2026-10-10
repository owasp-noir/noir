require "./prompt"

module LLM::PromptOverrides
  class_property filter_prompt : String = LLM::FILTER_PROMPT
  class_property analyze_prompt : String = LLM::ANALYZE_PROMPT
  class_property bundle_analyze_prompt : String = LLM::BUNDLE_ANALYZE_PROMPT
  class_property llm_optimize_prompt : String = <<-PROMPT
    Normalize the provided endpoint without changing which route it names.

    Allowed:
    - Rewriting path-parameter syntax to {name} (e.g. :id or <int:id> becomes {id})
    - Naming an unnamed wildcard (e.g. * becomes {path})
    - Correcting parameter types (query, json, form, header, cookie, path)

    Not allowed (such answers are discarded):
    - Changing, adding, removing, or re-casing any literal path text
    - Renaming parameters

    Guidelines:
    - Return the URL and parameters unchanged when nothing needs normalizing
    - Do not include explanations or comments
    - Output only the JSON result according to the schema
    PROMPT
end
