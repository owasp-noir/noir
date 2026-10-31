# Whether a JS statement that runs before an auth check only reads, so the
# check still comes first in effect. Shared by the Socket.IO and Next.js
# auth taggers, which both accept a check only when nothing a refused
# caller could use ran before it.
#
# An allow-list: a declaration counts when every call in it (tagged
# templates included) has a read-shaped name and nothing in it assigns or
# steps a value; a log line counts when its arguments call nothing.
# `fetch`, `query`, `execute`, `run`, `del`, `remove` and any name not
# recognised are not reads.
module Noir::JSReadShape
  extend self

  DECLARATION = /\A(?:const|let|var)\s+[^=]+?=(?![=>])\s*([\s\S]*?)\s*;?\z/
  LOG_CALL    = /\A(?:console|log|logger|this\s*\.\s*(?:log|logger))\s*\.\s*(?:log|info|debug|warn|trace|verbose|error|silly)\s*\(([\s\S]*)\)\s*;?\z/
  # A call or a tagged template: `name(` / `` name` ``.
  CALL = /(?<![\w$])([A-Za-z_$][\w$]*)\s*(?:\(|`)/
  # `getUser`, `findOne`, `loadConfig`, `slugToID`, `json`, `map`, …
  READ_NAME = /\A(?:(?:get|find|load|read|list|count|has|is|lookup|parse|select|validate)(?:[A-Z_\d][\w$]*)?|[a-z][\w$]*To[A-Z][\w$]*|json|text|formData|arrayBuffer|blob|headers|cookies|params|searchParams|keys|values|entries|map|filter|some|every|includes|indexOf|slice|split|trim|join|concat|at|toString|toLowerCase|toUpperCase|toISOString|startsWith|endsWith|parseInt|parseFloat|Number|String|Boolean|BigInt|URL|URLSearchParams|Date|now|Set|Map|Array|Object|from|isArray|require)\z/
  # Words a call scan meets that are not calls of a function.
  KEYWORDS = Set{"if", "for", "while", "switch", "catch", "return", "typeof", "await", "new", "async", "void", "in", "of"}
  # `x = 1`, `n++`, `--q[a]` in what should be a value.
  MUTATION = /\+\+|--|(?<![=!<>])=(?![=>])/
  # A request option other than GET: `{ method: "POST" }`.
  WRITE_METHOD = /\bmethod\s*:\s*(?:["'`](?!GET["'`])|[A-Za-z_$])/i

  def read_only?(statement : String) : Bool
    text = statement.strip
    if log = text.match(LOG_CALL)
      args = blank_strings(log[1])
      return !args.includes?("await") && !args.matches?(CALL)
    end
    declaration = text.match(DECLARATION) || return false
    value = declaration[1]
    return false if value.matches?(WRITE_METHOD)
    code = blank_strings(value)
    return false if code.matches?(MUTATION) || code.includes?("function")
    code.scan(CALL).all? { |call| KEYWORDS.includes?(call[1]) || call[1].matches?(READ_NAME) }
  end

  # String literals emptied; a template keeps its backticks so a tagged
  # template (`` sql`DELETE …` ``) still reads as a call.
  private def blank_strings(code : String) : String
    code.gsub(/"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'/, %("")).gsub(/`(?:[^`\\]|\\.)*`/, "``")
  end
end
