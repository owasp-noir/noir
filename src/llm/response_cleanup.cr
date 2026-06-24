module LLM
  # Strip the markdown ```json / ``` code fences that LLM providers sometimes
  # wrap JSON responses in, and trim surrounding whitespace. Shared by every
  # provider client so the cleanup rule has a single home.
  def self.strip_json_fences(text : String) : String
    text.gsub("```json", "").gsub("```", "").strip
  end
end
