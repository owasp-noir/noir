require "spec"
require "../../../src/utils/top_level_split"

private alias TLS = Noir::TopLevelSplit
private alias TLSRules = Noir::TopLevelSplit::Rules
private alias TLSNest = Noir::TopLevelSplit::Nest
private alias TLSEscape = Noir::TopLevelSplit::Escape
private alias TLSEmpties = Noir::TopLevelSplit::Empties

private ALL_BRACKETS = TLSNest::Paren | TLSNest::Bracket | TLSNest::Brace

private def tls_rules(**opts)
  TLSRules.new(**opts)
end

describe Noir::TopLevelSplit do
  describe "basic splitting" do
    it "splits a flat list" do
      TLS.split("a,b,c", ',', tls_rules).should eq ["a", "b", "c"]
    end

    it "strips each part when strip is true" do
      TLS.split(" a ,  b  , c ", ',', tls_rules(strip: true)).should eq ["a", "b", "c"]
    end

    it "keeps surrounding whitespace when strip is false" do
      TLS.split(" a , b ", ',', tls_rules(strip: false, empties: TLSEmpties::Keep))
        .should eq [" a ", " b "]
    end

    it "returns the whole input when no delimiter is present" do
      TLS.split("a b c", ',', tls_rules).should eq ["a b c"]
    end

    it "handles empty input" do
      TLS.split("", ',', tls_rules(empties: TLSEmpties::Keep)).should eq [""]
      TLS.split("", ',', tls_rules(empties: TLSEmpties::DropTrailing)).should eq [] of String
      TLS.split("", ',', tls_rules(empties: TLSEmpties::DropAll)).should eq [] of String
    end

    it "handles delimiter-only input" do
      TLS.split(",", ',', tls_rules(empties: TLSEmpties::Keep)).should eq ["", ""]
      TLS.split(",,,", ',', tls_rules(empties: TLSEmpties::Keep)).should eq ["", "", "", ""]
      TLS.split(",,,", ',', tls_rules(empties: TLSEmpties::DropAll)).should eq [] of String
    end
  end

  describe "nesting" do
    it "ignores delimiters inside parentheses" do
      TLS.split("f(a, b), c", ',', tls_rules).should eq ["f(a, b)", "c"]
    end

    it "ignores delimiters inside nested calls" do
      TLS.split("f(a, g(b, c)), d", ',', tls_rules).should eq ["f(a, g(b, c))", "d"]
    end

    it "ignores delimiters inside brackets and braces" do
      TLS.split("[1, 2], {3, 4}, 5", ',', tls_rules).should eq ["[1, 2]", "{3, 4}", "5"]
    end

    it "does not count a bracket kind that is not enabled" do
      # Angle is off by default, so `a < b` reads as a comparison, not a generic.
      TLS.split("a < b, c > d", ',', tls_rules).should eq ["a < b", "c > d"]
    end

    it "counts angle brackets when Nest::Angle is enabled" do
      angle = tls_rules(nest: ALL_BRACKETS | TLSNest::Angle)
      TLS.split("Map<String, String> m, x", ',', angle).should eq ["Map<String, String> m", "x"]
    end

    it "splits generic arguments with GENERICS_ONLY" do
      TLS.split("String, List<Map<String, Integer>>, int", ',', TLSRules::GENERICS_ONLY)
        .should eq ["String", " List<Map<String, Integer>>", " int"]
    end

    it "ignores parens under GENERICS_ONLY because they are not enabled" do
      TLS.split("f(a, b)", ',', TLSRules::GENERICS_ONLY).should eq ["f(a", " b)"]
    end
  end

  describe "per_kind" do
    it "keeps independent counters when per_kind is true" do
      # `[` leaves bracket depth at 1; the stray `)` clamps paren depth at 0,
      # so the comma is still nested and nothing splits.
      TLS.split("[a)b, c", ',', tls_rules(per_kind: true)).should eq ["[a)b, c"]
    end

    it "lets one kind cancel another when per_kind is false" do
      # `[` is +1 and `)` is -1 on the SAME counter, so the comma sees depth 0.
      TLS.split("[a)b, c", ',', tls_rules(per_kind: false)).should eq ["[a)b", "c"]
    end

    it "agrees on balanced input regardless of per_kind" do
      input = "f([1, 2], {3, 4}), g(5, 6)"
      expected = ["f([1, 2], {3, 4})", "g(5, 6)"]
      TLS.split(input, ',', tls_rules(per_kind: true)).should eq expected
      TLS.split(input, ',', tls_rules(per_kind: false)).should eq expected
    end

    it "differs on a mismatched brace/paren pair" do
      TLS.split("{a), b", ',', tls_rules(per_kind: true)).should eq ["{a), b"]
      TLS.split("{a), b", ',', tls_rules(per_kind: false)).should eq ["{a)", "b"]
    end
  end

  describe "clamp" do
    it "ignores a closer at depth zero when clamp is true" do
      TLS.split(")a, b", ',', tls_rules(clamp: true)).should eq [")a", "b"]
    end

    it "goes negative and suppresses later splits when clamp is false" do
      # Depth becomes -1 at `)` and never returns to exactly 0, so the comma
      # no longer splits.
      TLS.split(")a, b", ',', tls_rules(clamp: false)).should eq [")a, b"]
    end

    it "recovers to depth zero only when a matching opener follows" do
      # `))a, b` sits at -2 and stays nested; `))((a, b` climbs back to exactly
      # 0 and splits again. Under clamp: true both would have split.
      TLS.split("))a, b", ',', tls_rules(clamp: false)).should eq ["))a, b"]
      TLS.split("))((a, b", ',', tls_rules(clamp: false)).should eq ["))((a", "b"]
      TLS.split("))a, b", ',', tls_rules(clamp: true)).should eq ["))a", "b"]
    end

    it "clamps per counter when per_kind is also on" do
      TLS.split("))a, b", ',', tls_rules(clamp: true, per_kind: true)).should eq ["))a", "b"]
      TLS.split("))a, b", ',', tls_rules(clamp: false, per_kind: true)).should eq ["))a, b"]
    end
  end

  describe "quotes" do
    it "does not split inside a quoted run" do
      TLS.split("a, \"b, c\", d", ',', tls_rules).should eq ["a", "\"b, c\"", "d"]
    end

    it "retains the quote characters in the emitted part" do
      TLS.split("\"x\"", ',', tls_rules).should eq ["\"x\""]
    end

    it "does not treat brackets inside quotes as nesting" do
      TLS.split("\"(\", \")\"", ',', tls_rules).should eq ["\"(\"", "\")\""]
    end

    it "closes a run only with the character that opened it" do
      TLS.split("\"it's fine\", next", ',', tls_rules).should eq ["\"it's fine\"", "next"]
    end

    it "treats every configured quote character as an opener" do
      TLS.split("'a, b', c", ',', tls_rules).should eq ["'a, b'", "c"]
    end

    it "disables quote handling entirely when quotes is empty" do
      TLS.split("\"a, b\", c", ',', tls_rules(quotes: "")).should eq ["\"a", "b\"", "c"]
    end

    it "runs an unterminated quote to end of input" do
      TLS.split("a, \"b, c", ',', tls_rules).should eq ["a", "\"b, c"]
    end

    it "keeps an unterminated quote open across brackets" do
      TLS.split("a, \"b(, c", ',', tls_rules).should eq ["a", "\"b(, c"]
    end

    it "supports backticks for template literals under Rules::JS" do
      TLS.split("`/a/${x, y}`, handler", ',', TLSRules::JS).should eq ["`/a/${x, y}`", "handler"]
    end
  end

  describe "Escape::None" do
    it "treats a backslash as an ordinary character inside quotes" do
      # The run closes at the second `"`, so the following comma splits.
      TLS.split("\"a\\\", b", ',', tls_rules(escape: TLSEscape::None))
        .should eq ["\"a\\\"", "b"]
    end

    it "treats a backslash as an ordinary character outside quotes" do
      TLS.split("a\\, b", ',', tls_rules(escape: TLSEscape::None)).should eq ["a\\", "b"]
    end

    it "keeps a trailing backslash" do
      TLS.split("a\\", ',', tls_rules(escape: TLSEscape::None)).should eq ["a\\"]
    end
  end

  describe "Escape::InQuotes" do
    it "does not close the run on an escaped quote" do
      TLS.split("\"a\\\"b\", c", ',', tls_rules(escape: TLSEscape::InQuotes))
        .should eq ["\"a\\\"b\"", "c"]
    end

    it "retains the backslash in the emitted part" do
      # Matches every implementation this module replaces: they append the
      # char and only afterwards decide it was an escape.
      TLS.split("\"a\\nb\"", ',', tls_rules(escape: TLSEscape::InQuotes)).should eq ["\"a\\nb\""]
    end

    it "treats an escaped backslash as consumed so the next quote closes" do
      TLS.split("\"a\\\\\", b", ',', tls_rules(escape: TLSEscape::InQuotes))
        .should eq ["\"a\\\\\"", "b"]
    end

    it "leaves a backslash outside quotes ordinary" do
      TLS.split("a\\, b", ',', tls_rules(escape: TLSEscape::InQuotes)).should eq ["a\\", "b"]
    end

    it "handles a trailing backslash inside an unterminated run" do
      TLS.split("a, \"b\\", ',', tls_rules(escape: TLSEscape::InQuotes)).should eq ["a", "\"b\\"]
    end

    it "handles a trailing backslash at end of input outside quotes" do
      TLS.split("a, b\\", ',', tls_rules(escape: TLSEscape::InQuotes)).should eq ["a", "b\\"]
    end
  end

  describe "Escape::Always" do
    it "escapes the delimiter outside quotes" do
      TLS.split("a\\,b, c", ',', tls_rules(escape: TLSEscape::Always)).should eq ["a\\,b", "c"]
    end

    it "escapes a quote outside quotes so no run opens" do
      TLS.split("a\\\", b", ',', tls_rules(escape: TLSEscape::Always)).should eq ["a\\\"", "b"]
    end

    it "escapes a bracket outside quotes so depth is untouched" do
      TLS.split("a\\(, b", ',', tls_rules(escape: TLSEscape::Always)).should eq ["a\\(", "b"]
    end

    it "still escapes inside quotes" do
      TLS.split("\"a\\\"b\", c", ',', tls_rules(escape: TLSEscape::Always))
        .should eq ["\"a\\\"b\"", "c"]
    end

    it "keeps a trailing backslash" do
      TLS.split("a, b\\", ',', tls_rules(escape: TLSEscape::Always)).should eq ["a", "b\\"]
    end
  end

  describe "Empties" do
    it "keeps every empty part under Keep" do
      TLS.split("a,,b,", ',', tls_rules(empties: TLSEmpties::Keep)).should eq ["a", "", "b", ""]
    end

    it "drops only the final empty part under DropTrailing" do
      TLS.split("a,,b,", ',', tls_rules(empties: TLSEmpties::DropTrailing)).should eq ["a", "", "b"]
    end

    it "drops exactly one trailing empty, not a run of them" do
      TLS.split("a,,", ',', tls_rules(empties: TLSEmpties::DropTrailing)).should eq ["a", ""]
    end

    it "leaves a non-empty final part alone under DropTrailing" do
      TLS.split("a,,b", ',', tls_rules(empties: TLSEmpties::DropTrailing)).should eq ["a", "", "b"]
    end

    it "drops every empty part under DropAll" do
      TLS.split(",a,,b,,", ',', tls_rules(empties: TLSEmpties::DropAll)).should eq ["a", "b"]
    end

    it "treats a whitespace-only part as empty because strip runs first" do
      TLS.split("a,   ,b", ',', tls_rules(strip: true, empties: TLSEmpties::DropAll))
        .should eq ["a", "b"]
      TLS.split("a,   ,b", ',', tls_rules(strip: false, empties: TLSEmpties::DropAll))
        .should eq ["a", "   ", "b"]
    end

    it "drops a whitespace-only trailing part under DropTrailing when stripping" do
      TLS.split("a,  ", ',', tls_rules(strip: true, empties: TLSEmpties::DropTrailing))
        .should eq ["a"]
      TLS.split("a,  ", ',', tls_rules(strip: false, empties: TLSEmpties::DropTrailing))
        .should eq ["a", "  "]
    end
  end

  describe "multi-character delimiter" do
    it "splits on a two-character separator" do
      TLS.split("a :> b :> c", ":>", tls_rules).should eq ["a", "b", "c"]
    end

    it "does not fire on a partial match" do
      TLS.split("a : b :> c", ":>", tls_rules).should eq ["a : b", "c"]
    end

    it "does not fire on a lone leading character of the separator" do
      TLS.split("a:b", ":>", tls_rules).should eq ["a:b"]
    end

    it "handles a separator that itself contains bracket characters" do
      # `:<|>` carries `<` and `>`; the separator match must win over the
      # angle-depth bookkeeping or the rest of the input never splits.
      angle = tls_rules(nest: ALL_BRACKETS | TLSNest::Angle)
      TLS.split("Get :<|> Post :<|> Put", ":<|>", angle).should eq ["Get", "Post", "Put"]
    end

    it "ignores a separator inside quotes" do
      TLS.split("\"a || b\" || c", "||", tls_rules).should eq ["\"a || b\"", "c"]
    end

    it "ignores a separator nested inside brackets" do
      TLS.split("f(a || b) || c", "||", tls_rules).should eq ["f(a || b)", "c"]
    end

    it "finds an overlapping match instead of skipping past it" do
      # Naively flushing the whole buffered prefix on mismatch would miss the
      # "aab" that starts at index 1.
      TLS.split("xaaaby", "aab", tls_rules(strip: false, empties: TLSEmpties::Keep))
        .should eq ["xa", "y"]
    end

    it "matches leftmost on a repeated separator character" do
      TLS.split("a|||b", "||", tls_rules(strip: false, empties: TLSEmpties::Keep))
        .should eq ["a", "|b"]
    end

    it "emits an empty part between adjacent separators" do
      TLS.split("a&&&&b", "&&", tls_rules(strip: false, empties: TLSEmpties::Keep))
        .should eq ["a", "", "b"]
    end

    it "leaves a dangling partial separator at end of input in the tail" do
      TLS.split("a :> b :", ":>", tls_rules(strip: false, empties: TLSEmpties::Keep))
        .should eq ["a ", " b :"]
    end

    it "handles input that is only the separator" do
      TLS.split("||", "||", tls_rules(empties: TLSEmpties::Keep)).should eq ["", ""]
    end

    it "behaves like the Char overload for a one-character String" do
      TLS.split("a,b,c", ",", tls_rules).should eq ["a", "b", "c"]
      TLS.split("f(a, b), c", ",", tls_rules).should eq ["f(a, b)", "c"]
    end

    it "returns the whole input for an empty separator" do
      TLS.split(" a,b ", "", tls_rules(strip: true)).should eq ["a,b"]
      TLS.split(" a,b ", "", tls_rules(strip: false, empties: TLSEmpties::Keep)).should eq [" a,b "]
    end
  end

  # The `String`-delimiter overload had unit coverage but no production caller
  # until haskell/servant.cr (`,` / `:>` / `:<|>`) and
  # specification/traefik.cr (`||` / `&&`) were converted. These exercise the
  # buffering paths those two rule sets actually reach.
  describe "multi-character delimiter, production rule sets" do
    servant = tls_rules(
      nest: ALL_BRACKETS,
      quotes: "\"",
      escape: TLSEscape::InQuotes,
      strip: true,
      empties: TLSEmpties::DropAll,
      per_kind: true,
      clamp: true,
    )
    traefik = tls_rules(
      nest: TLSNest::Paren,
      quotes: "",
      escape: TLSEscape::None,
      strip: true,
      empties: TLSEmpties::DropAll,
      per_kind: false,
      clamp: true,
    )

    it "emits a late-failing partial match verbatim" do
      # Three of the four separator characters match before the fourth fails;
      # the buffered `:<|` must land in the part, not be dropped.
      TLS.split("a :<| b :<|> c", ":<|>", servant).should eq ["a :<| b", "c"]
    end

    it "retries a late-failing partial match against a real match" do
      # `:<|` fails at `:`, and the retry must find the `:<|>` that starts one
      # character later rather than skipping the whole buffer past it.
      TLS.split("a :<|:<|> b", ":<|>", servant).should eq ["a :<|", "b"]
    end

    it "keeps a trailing partial separator in the tail" do
      TLS.split("a :> b :", ":>", servant).should eq ["a", "b :"]
      TLS.split("a :<|> b :<|", ":<|>", servant).should eq ["a", "b :<|"]
      TLS.split("a || b |", "||", traefik).should eq ["a", "b |"]
    end

    it "does not confuse two separators sharing a leading character" do
      # Servant calls the same splitter with `:>` and `:<|>`; each call must
      # see only its own separator.
      api = "\"users\" :> Get '[JSON] [User] :<|> \"posts\" :> Post '[JSON] Post"
      TLS.split(api, ":<|>", servant)
        .should eq ["\"users\" :> Get '[JSON] [User]", "\"posts\" :> Post '[JSON] Post"]
      TLS.split("\"users\" :> Get '[JSON] [User]", ":>", servant)
        .should eq ["\"users\"", "Get '[JSON] [User]"]
    end

    it "treats separator angle brackets as ordinary characters when Angle is off" do
      # `:<|>` carries `<` and `>`; with `Nest::Angle` disabled they must not
      # touch the depth counters, or a buffered `<` would suppress later splits.
      TLS.split("A :<|> B :<|> C", ":<|>", servant).should eq ["A", "B", "C"]
      TLS.split("a < b :> c > d", ":>", servant).should eq ["a < b", "c > d"]
    end

    it "does not split a servant separator inside a promoted list or parens" do
      TLS.split("\"a\" :> (X :<|> Y) :<|> Z", ":<|>", servant).should eq ["\"a\" :> (X :<|> Y)", "Z"]
      TLS.split("Get '[JSON] [Map A B] :<|> Z", ":<|>", servant).should eq ["Get '[JSON] [Map A B]", "Z"]
    end

    it "keeps a servant separator inside a double-quoted segment" do
      TLS.split("Summary \"does a :<|> b\" :<|> Z", ":<|>", servant)
        .should eq ["Summary \"does a :<|> b\"", "Z"]
    end

    it "leaves backticks and quotes inert in a traefik rule" do
      # `quotes: ""` is load-bearing: Traefik matcher arguments use backticks
      # and may contain lone quotes, so any quote handling would swallow the
      # rest of the rule.
      TLS.split("Host(`a.com`) && (PathPrefix(`/x`) || PathPrefix(`/y`))", "&&", traefik)
        .should eq ["Host(`a.com`)", "(PathPrefix(`/x`) || PathPrefix(`/y`))"]
      TLS.split("Path(`/it's`) || Path(`/\"q\"`)", "||", traefik)
        .should eq ["Path(`/it's`)", "Path(`/\"q\"`)"]
    end

    it "hides a traefik separator nested in matcher arguments" do
      TLS.split("Header(`X-A`, `a||b`) || Path(`/x`)", "||", traefik)
        .should eq ["Header(`X-A`, `a||b`)", "Path(`/x`)"]
      TLS.split("Query(`a=1&&b=2`) && Path(`/y`)", "&&", traefik)
        .should eq ["Query(`a=1&&b=2`)", "Path(`/y`)"]
    end

    it "does not count regexp brackets in a traefik rule" do
      TLS.split("HostRegexp(`{sub:[a-z]+}.a.com`) && PathPrefix(`/v1`)", "&&", traefik)
        .should eq ["HostRegexp(`{sub:[a-z]+}.a.com`)", "PathPrefix(`/v1`)"]
    end

    it "drops interior and edge empties for both rule sets" do
      TLS.split("a :> :> b", ":>", servant).should eq ["a", "b"]
      TLS.split(":> a :>", ":>", servant).should eq ["a"]
      TLS.split("|| a || || b ||", "||", traefik).should eq ["a", "b"]
      TLS.split("", ":<|>", servant).should eq [] of String
      TLS.split("&&", "&&", traefik).should eq [] of String
    end

    it "does not desync a multi-character separator after multi-byte matchers" do
      TLS.split("Host(`한국.com`) && Path(`/🚀`)", "&&", traefik)
        .should eq ["Host(`한국.com`)", "Path(`/🚀`)"]
      TLS.split("한국 :<|> 語 :<|> 🚀", ":<|>", servant).should eq ["한국", "語", "🚀"]
    end
  end

  describe "non-ASCII input" do
    it "splits Korean arguments correctly" do
      TLS.split("경로, 처리기, 옵션", ',', tls_rules).should eq ["경로", "처리기", "옵션"]
    end

    it "does not split a delimiter inside a Korean quoted argument" do
      TLS.split("\"/한국, 경로\", 처리기", ',', tls_rules).should eq ["\"/한국, 경로\"", "처리기"]
    end

    it "handles emoji inside a quoted argument" do
      TLS.split("\"/api/🚀, /b\", handler", ',', tls_rules).should eq ["\"/api/🚀, /b\"", "handler"]
    end

    it "keeps multi-byte characters intact around nesting" do
      TLS.split("f(한, 국), 어", ',', tls_rules).should eq ["f(한, 국)", "어"]
    end

    it "does not desync a multi-character separator after multi-byte text" do
      TLS.split("한국 || 語 || 🚀", "||", tls_rules).should eq ["한국", "語", "🚀"]
    end

    it "handles an escaped quote next to multi-byte content" do
      TLS.split("\"한\\\"국\", 어", ',', tls_rules).should eq ["\"한\\\"국\"", "어"]
    end
  end

  describe "Rules::CPP" do
    it "keeps a whole nested handler call as one argument" do
      input = "app->Get(\"/users/{id}\", [](const Req &r, Res &s) { s.set(\"a,b\"); })"
      TLS.split(input, ',', TLSRules::CPP).should eq [input]
    end

    it "splits an oatpp ENDPOINT macro argument list" do
      TLS.split("\"GET\", \"/users/{id}\", getUser, PATH(Int32, id)", ',', TLSRules::CPP)
        .should eq ["\"GET\"", "\"/users/{id}\"", "getUser", "PATH(Int32, id)"]
    end

    it "drops the trailing empty argument" do
      TLS.split("\"GET\", \"/a\",", ',', TLSRules::CPP).should eq ["\"GET\"", "\"/a\""]
    end

    it "keeps an interior empty argument" do
      TLS.split("\"GET\", , \"/a\"", ',', TLSRules::CPP).should eq ["\"GET\"", "", "\"/a\""]
    end

    it "does not treat a single quote as a quote character" do
      TLS.split("'a', 'b'", ',', TLSRules::CPP).should eq ["'a'", "'b'"]
    end

    it "uses per-kind clamped counters" do
      TLS.split("[a)b, c", ',', TLSRules::CPP).should eq ["[a)b, c"]
    end
  end

  describe "Rules::JAVA" do
    it "splits an annotation argument list and strips each part" do
      TLS.split("value = \"/users/{id}\", method = RequestMethod.GET", ',', TLSRules::JAVA)
        .should eq ["value = \"/users/{id}\"", "method = RequestMethod.GET"]
    end

    it "keeps a nested lambda handler as one argument" do
      input = "\"/a\", ctx -> { ctx.json(map(\"x\", 1)); }"
      TLS.split(input, ',', TLSRules::JAVA).should eq ["\"/a\"", "ctx -> { ctx.json(map(\"x\", 1)); }"]
    end

    it "splits a concatenated path expression on plus" do
      TLS.split("BASE + \"/users\" + suffix", '+', TLSRules::JAVA)
        .should eq ["BASE", "\"/users\"", "suffix"]
    end

    it "drops a trailing empty part but keeps an interior one" do
      TLS.split("a, , b,", ',', TLSRules::JAVA).should eq ["a", "", "b"]
    end

    it "treats a single quote as a quote character, unlike Rules::CPP" do
      TLS.split("sep(','), x", ',', TLSRules::JAVA).should eq ["sep(',')", "x"]
    end

    # The axis that separates this preset from quarkus.cr and wicket.cr, which
    # add Nest::Angle: here a generic argument list breaks apart at its comma.
    it "does not count angle brackets, so a generic type splits" do
      TLS.split("Map<String, Integer> m", ',', TLSRules::JAVA).should eq ["Map<String", "Integer> m"]
    end

    it "uses one shared clamped depth across bracket kinds" do
      TLS.split("[a)b, c", ',', TLSRules::JAVA).should eq ["[a)b", "c"]
    end
  end

  describe "Rules::JS" do
    it "splits a decorator argument list and strips each part" do
      TLS.split("'users/:id', { name: 'x', tags: [1, 2] }", ',', TLSRules::JS)
        .should eq ["'users/:id'", "{ name: 'x', tags: [1, 2] }"]
    end

    # Backticks are the axis that separates this preset from JAVA/CPP: a
    # template literal wraps most JS route strings, and without backtick
    # quoting the comma inside `${...}` would break the route in half.
    it "treats a backtick template literal as one quoted run" do
      TLS.split("`/users/${ids.join(',')}/posts`, handler", ',', TLSRules::JS)
        .should eq ["`/users/${ids.join(',')}/posts`", "handler"]
    end

    it "keeps a nested template literal intact" do
      TLS.split("`${`${x, y}`, z}`, tail", ',', TLSRules::JS)
        .should eq ["`${`${x, y}`, z}`", "tail"]
    end

    it "keeps an arrow function with its own parameter list as one part" do
      TLS.split("'/x', (req, res) => res.send('ok'), next", ',', TLSRules::JS)
        .should eq ["'/x'", "(req, res) => res.send('ok')", "next"]
    end

    it "splits a concatenated path expression on plus" do
      TLS.split("BASE + `/users/${id}`", '+', TLSRules::JS)
        .should eq ["BASE", "`/users/${id}`"]
    end

    # DropAll, unlike JAVA's DropTrailing: interior empties vanish too, so a
    # caller cannot index parts positionally.
    it "drops interior and trailing empty parts" do
      TLS.split("a, , b,", ',', TLSRules::JS).should eq ["a", "b"]
    end

    it "retains a backslash escaping a quote inside a run" do
      TLS.split("'a\\', b'", ',', TLSRules::JS).should eq ["'a\\', b'"]
    end

    # The axis that separates this preset from typescript/trpc.cr, whose
    # file-local rules share one depth counter and would split here.
    it "uses per-kind clamped depth counters" do
      TLS.split("[a)b, c", ',', TLSRules::JS).should eq ["[a)b, c"]
    end

    it "does not count angle brackets, unlike nextjs.cr's file-local rules" do
      TLS.split("Promise<a, b>", ',', TLSRules::JS).should eq ["Promise<a", "b>"]
    end

    it "keeps a non-ASCII quoted argument in one part" do
      TLS.split("'안녕, 세상', handler", ',', TLSRules::JS)
        .should eq ["'안녕, 세상'", "handler"]
    end
  end
end
