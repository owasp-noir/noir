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
  # A fenced block somewhere inside prose ("Here are the endpoints: ```json
  # {...} ``` Hope this helps").
  EMBEDDED_FENCE = /```[A-Za-z0-9_+.\-]*[^\S\n]*\r?\n(.*?)\r?\n[^\S\n]*```/m

  # Strip the markdown ```json / ``` code fences that LLM providers sometimes
  # wrap JSON responses in, and trim surrounding whitespace. Shared by every
  # provider client so the cleanup rule has a single home.
  #
  # A reply that is not a bare JSON value after that — the model wrapped it
  # in prose — yields the first fenced block, else the span from the first
  # `{` to the last `}`. Without this, `JSON.parse` failed on the whole reply
  # and every endpoint in it was lost.
  def self.strip_json_fences(text : String) : String
    stripped = text.strip
    if stripped.starts_with?("```")
      stripped = stripped.sub(LEADING_FENCE, "").sub(TRAILING_FENCE, "").strip
    end
    return stripped if json_shaped?(stripped)

    if block = EMBEDDED_FENCE.match(stripped).try(&.[1].strip)
      return block if json_shaped?(block)
    end

    first = stripped.index('{')
    last = stripped.rindex('}')
    return stripped unless first && last && first < last
    stripped[first..last]
  end

  private def self.json_shaped?(text : String) : Bool
    (text.starts_with?('{') && text.ends_with?('}')) ||
      (text.starts_with?('[') && text.ends_with?(']'))
  end
end
