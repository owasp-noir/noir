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
  # How many fenced blocks, and how many `{`, the prose fallbacks try before
  # giving up; each `{` try scans to the end of a reply that never closes it.
  MAX_FENCED_BLOCKS = 16
  MAX_OBJECT_STARTS = 16

  # Strip the markdown ```json / ``` code fences that LLM providers sometimes
  # wrap JSON responses in, and trim surrounding whitespace. Shared by every
  # provider client so the cleanup rule has a single home. Deliberately no
  # more than that: picking the JSON out of prose needs to know which key the
  # caller expects (`json_reply`), and a client that guessed first would
  # hand it the wrong object.
  def self.strip_json_fences(text : String) : String
    stripped = text.strip
    return stripped unless stripped.starts_with?("```")

    stripped.sub(LEADING_FENCE, "").sub(TRAILING_FENCE, "").strip
  end

  # Why a reply that did not end normally is unusable, or nil. `reason` is
  # OpenAI's `finish_reason`, Ollama's `done_reason` or Anthropic's
  # `stop_reason` (`length` / `max_tokens` for a reply cut off by the output
  # limit). An empty reply is otherwise silent: the caller would read it as
  # "no endpoints".
  def self.unfinished_reply(reason : String?, content : String) : String?
    case reason
    when "length", "max_tokens"
      "AI reply was truncated by the model's output limit; endpoints after the cut are lost (a lower --ai-max-token sends smaller bundles)"
    when "incomplete"
      "AI reply stream ended before the reply finished; endpoints after the cut are lost"
    when "content_filter"
      "AI reply was blocked by the provider's content filter"
    else
      "AI provider returned an empty reply#{" (finish reason: #{reason})" if reason}" if content.blank?
    end
  end

  # The JSON object in an LLM reply that carries `key`, or nil.
  #
  # A model wraps its JSON in prose ("Here are the endpoints: ...", "Note
  # /users/{id} too"), puts a code block or a `{"thought": ...}` before it,
  # or answers with some other object (`{"error": "context length
  # exceeded"}`). Only an object holding the expected key is the answer, so
  # the candidates are tried in turn: the reply, its fenced blocks (```json
  # ones first), then each balanced top-level `{...}`. An empty `{}` reply is
  # returned as-is — the model saying "nothing here" in the asked-for shape.
  def self.json_reply(text : String, key : String) : Hash(String, JSON::Any)?
    stripped = strip_json_fences(text)
    if object = object_with(stripped, key)
      return object
    end

    json_blocks, other_blocks = text.scan(FENCED_BLOCK).partition { |match| match[1].compare("json", case_insensitive: true) == 0 }
    (json_blocks + other_blocks).first(MAX_FENCED_BLOCKS).each do |match|
      if object = object_with(match[2].strip, key)
        return object
      end
    end

    first_object_with(text, key) || parse_object(stripped).try { |empty| empty if empty.empty? }
  end

  # The complete objects at the head of a `"key": [` list that never closes,
  # or nil: what is left of a reply cut off by the output limit. Stops at
  # the first item that is not a whole object, so nothing past the cut (or
  # past the list's end) is taken.
  def self.salvage_list(text : String, key : String) : Array(JSON::Any)?
    match = text.match(/"#{Regex.escape(key)}"\s*:\s*\[/) || return
    bytes = text.to_slice
    pos = match.byte_end(0)
    items = [] of JSON::Any
    loop do
      while pos < bytes.size && (bytes[pos].unsafe_chr.ascii_whitespace? || ',' === bytes[pos])
        pos += 1
      end
      break unless pos < bytes.size && '{' === bytes[pos]
      stop = balanced_end(bytes, pos) || break
      begin
        items << JSON.parse(text.byte_slice(pos, stop - pos + 1))
      rescue JSON::ParseException
        break
      end
      pos = stop + 1
    end
    items unless items.empty?
  end

  private def self.parse_object(text : String) : Hash(String, JSON::Any)?
    return if text.empty?
    JSON.parse(text).as_h?
  rescue JSON::ParseException
    nil
  end

  private def self.object_with(text : String, key : String) : Hash(String, JSON::Any)?
    object = parse_object(text)
    object if object && object.has_key?(key)
  end

  # Top-level objects only: a balanced span without the key (`{id}` in
  # prose, a `{"thought": ...}` preamble) is skipped whole, and an object
  # that never closes ends the search. Descending into either would hand
  # back a nested fragment — one endpoint object out of a truncated reply.
  #
  # Byte-wise: `{`, `}`, `"` and `\` are ASCII, so they never occur inside
  # a multi-byte character and the slice boundaries are character ones.
  private def self.first_object_with(text : String, key : String) : Hash(String, JSON::Any)?
    bytes = text.to_slice
    start = 0
    MAX_OBJECT_STARTS.times do
      start = bytes.index('{'.ord.to_u8, start) || return
      stop = balanced_end(bytes, start)
      return if stop.nil?
      if object = object_with(text.byte_slice(start, stop - start + 1), key)
        return object
      end
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
