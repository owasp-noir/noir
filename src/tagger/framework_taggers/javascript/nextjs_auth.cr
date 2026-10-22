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
  SESSION_DENIED = /\bif\s*\(.*(?:!\s*session\b|\bsession\s*(?:\?\.\w+\s*)*(?:===?|!==?)\s*(?:null|undefined)\b|process\.env\.\w+\s*!==?|!==?\s*process\.env\.\w+)/
  # ponytail: the body is the next lines up to the closing brace at column 0,
  # capped; a handler nested in an object literal stops at the cap instead.
  MAX_BODY_LINES = 40

  def self.target_techs : Array(String)
    ["js_nextjs"]
  end

  private def check_endpoint(endpoint : Endpoint)
    target = endpoint.handler || endpoint.details.code_paths.first?
    return unless target && (path = target.path) && (line = target.line)
    return unless (lines = read_file_lines(path)) && line >= 1 && line <= lines.size

    body = lines[(line - 1)...{line - 1 + MAX_BODY_LINES, lines.size}.min]
    if ends = body.index(1, &.starts_with?('}'))
      body = body[0..ends]
    end
    body.each_with_index do |text, i|
      next unless code_only(text).matches?(UNAUTHORIZED)
      condition = body[{i - 3, 0}.max..i].reverse.find(&.matches?(SESSION_DENIED))
      next unless condition
      endpoint.add_tag(Tag.new("auth", "Protected by Next.js handler check `#{condition.strip.rchop('{').strip}` (replies 401)", "nextjs_auth"))
      return
    end
  end
end
