require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "nextjs_auth", name: "Next.js Auth Tagger", desc: "Identifies Next.js route handlers that reply 401 without a session or shared secret", order: 270)]
class NextjsAuthTagger < FrameworkTagger
  # Next.js has no route-level guard syntax: an API route checks the caller
  # in its own body (`if (!session) return NextResponse.json(.., { status:
  # 401 })`). A 401 reply under a condition on the session, or on a value
  # compared with a `process.env` secret, is that check. A 401 under any
  # other condition (`if (!user)` after a password lookup) is a login
  # failure anonymous callers are meant to reach, so it does not count.
  UNAUTHORIZED   = /\bstatus(?:Code)?\s*(?::|\()\s*401\b/
  ENV_SECRET     = /process\.env\.\w*(?:KEY|SECRET|TOKEN)\w*/
  SESSION_DENIED = /\bif\s*\(.*(?:!\s*session\b|\bsession\s*(?:\?\.\w+\s*)*(?:===?|!==?)\s*(?:null|undefined)\b|#{ENV_SECRET}\s*!==?|!==?\s*#{ENV_SECRET})/
  # A pages-router handler serves every verb from one body; a 401 after a
  # `req.method` branch guards only some of them. A branch that just
  # refuses other verbs with 405 leaves one verb, so it does not count.
  METHOD_BRANCH = /\breq(?:uest)?\.method\b/
  # How far above the 401 its `if` may sit (a Prettier-wrapped reply).
  CONDITION_LOOKBACK = 6

  def self.target_techs : Array(String)
    ["js_nextjs"]
  end

  private def check_endpoint(endpoint : Endpoint)
    target = endpoint.handler || endpoint.details.code_paths.first?
    return unless target && (path = target.path) && (line = target.line)
    return unless (lines = read_file_lines(path)) && line >= 1 && line <= lines.size

    code = function_body(lines, line - 1)
    code.each_with_index do |text, i|
      break if text.matches?(METHOD_BRANCH) && code[i, 3].none?(&.includes?("405"))
      next unless text.matches?(UNAUTHORIZED)
      i.downto({i - CONDITION_LOOKBACK, 0}.max) do |j|
        # A block closed between the `if` and the 401 is not the 401's.
        break if j < i && code[j].strip == "}"
        next unless code[j].matches?(SESSION_DENIED)
        endpoint.add_tag(Tag.new("auth", "Protected by Next.js handler check `#{code[j].strip.rchop('{').strip}` (replies 401)", "nextjs_auth"))
        return
      end
    end
  end

  # The comment-stripped lines from `start` to the brace that closes the
  # first one opened from there, or to the first `;` when a statement (an
  # `import` at a line-1 fallback) ends before any brace opens.
  private def function_body(lines : Array(String), start : Int32) : Array(String)
    body = [] of String
    depth = 0
    opened = false
    lines[start..].each do |raw|
      text = code_only(raw)
      body << text
      depth += text.count('{') - text.count('}')
      opened ||= text.includes?('{')
      break if opened ? depth <= 0 : text.rstrip.ends_with?(';')
    end
    body
  end
end
