require "json"

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
  # A fenced block anywhere in the reply, with its language tag.
  FENCED_BLOCK = /```([A-Za-z0-9_+.\-]*)[^\S\n]*\r?\n(.*?)\r?\n[^\S\n]*```/m
  # How many `{` the prose fallback tries before giving up; each try scans
  # to the end of the reply when the object never closes.
  MAX_OBJECT_STARTS = 16

  # Strip the markdown ```json / ``` code fences that LLM providers sometimes
  # wrap JSON responses in, and trim surrounding whitespace. Shared by every
  # provider client so the cleanup rule has a single home.
  #
  # A model also wraps the JSON in prose ("Here are the endpoints: ...",
  # "Note /users/{id} too"), and `JSON.parse` on the whole reply then lost
  # every endpoint in it. So the first candidate that actually parses wins:
  # the reply itself, a fenced block (```json ones first), the reply with
  # its outer fence removed, then the first balanced `{...}` in the text.
  # Nothing parsing returns the fence-stripped reply, for the caller to
  # reject.
  def self.strip_json_fences(text : String) : String
    stripped = text.strip
    return stripped if parses?(stripped)

    json_blocks, other_blocks = text.scan(FENCED_BLOCK).partition { |match| match[1].compare("json", case_insensitive: true) == 0 }
    (json_blocks + other_blocks).each do |match|
      block = match[2].strip
      return block if parses?(block)
    end

    unfenced = stripped
    if unfenced.starts_with?("```")
      unfenced = unfenced.sub(LEADING_FENCE, "").sub(TRAILING_FENCE, "").strip
      return unfenced if parses?(unfenced)
    end

    first_json_object(text) || unfenced
  end

  private def self.parses?(text : String) : Bool
    return false if text.empty?
    JSON.parse(text)
    true
  rescue JSON::ParseException
    false
  end

  # Top-level objects only: a balanced span that does not parse (`{id}` in
  # prose) is skipped whole, and an object that never closes ends the
  # search. Descending into either would hand back a nested fragment — one
  # endpoint object out of a truncated reply — that reads as a valid reply
  # with no endpoints.
  #
  # Byte-wise: `{`, `}`, `"` and `\` are ASCII, so they never occur inside
  # a multi-byte character and the slice boundaries are character ones.
  private def self.first_json_object(text : String) : String?
    bytes = text.to_slice
    start = 0
    MAX_OBJECT_STARTS.times do
      start = bytes.index('{'.ord.to_u8, start) || return
      stop = balanced_end(bytes, start)
      return if stop.nil?
      candidate = text.byte_slice(start, stop - start + 1)
      return candidate if parses?(candidate)
      start = stop + 1
    end
    nil
  end

  private def self.balanced_end(bytes : Bytes, start : Int32) : Int32?
    depth = 0
    in_string = false
    escaped = false
    (start...bytes.size).each do |i|
      byte = bytes[i]
      if in_string
        if escaped
          escaped = false
        elsif '\\' === byte
          escaped = true
        elsif '"' === byte
          in_string = false
        end
      elsif '"' === byte
        in_string = true
      elsif '{' === byte
        depth += 1
      elsif '}' === byte
        depth -= 1
        return i if depth == 0
      end
    end
    nil
  end
end
