module LLM
  # A markdown fence only ever wraps the *whole* payload, so both patterns
  # are anchored. The previous `gsub("```json", "").gsub("```", "")` ran over
  # the entire response and was wrong in both directions:
  #
  #   * backticks the model quoted from the code it was reading (inside a
  #     `snippet` or `description` string value) were deleted from the data,
  #     silently corrupting it;
  #   * only the exact lowercase `json` tag was recognised, so ```` ```JSON ````
  #     or ```` ```javascript ```` left the bare language word in front of the
  #     JSON — `JSON.parse` then failed and the caller returned "", which the
  #     analyzer reads as "this code defines no endpoints".
  #
  # The tag is matched case-insensitively and generically (any language word),
  # since which one the model picks is not something we control.
  LEADING_FENCE  = /\A```[A-Za-z0-9_+.\-]*[^\S\n]*\r?\n?/
  TRAILING_FENCE = /\r?\n?[^\S\n]*```\s*\z/

  # Strip the markdown ```json / ``` code fences that LLM providers sometimes
  # wrap JSON responses in, and trim surrounding whitespace. Shared by every
  # provider client so the cleanup rule has a single home.
  def self.strip_json_fences(text : String) : String
    stripped = text.strip
    return stripped unless stripped.starts_with?("```")

    stripped.sub(LEADING_FENCE, "").sub(TRAILING_FENCE, "").strip
  end
end
