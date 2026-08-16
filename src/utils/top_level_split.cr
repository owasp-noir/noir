module Noir
  # Splits a delimited list at the top nesting level, respecting quoted runs
  # and (optionally) backslash escapes.
  #
  # This replaces ~44 hand-rolled copies of the same loop spread across
  # `src/analyzer/analyzers/`, `src/analyzer/engines/` and `src/miniparsers/`,
  # 19 of which were byte-identical to a sibling. A quote- or escape-handling
  # bug used to need 44 separate fixes; the copies had already drifted along
  # seven independent axes (see `Rules`), so "just pick one and inline it"
  # would have changed detection for whichever analyzers lost their variant.
  #
  # Implementation note — why a single forward pass into a `String::Builder`
  # and not `text[i]` / `text[start...index]`:
  # `String#[](Int)` and char-range slicing are O(index) the moment a string
  # contains one multi-byte UTF-8 codepoint, because Crystal has to walk the
  # bytes to find the char boundary. Several of the copies being replaced
  # here indexed per char inside a `while` loop, making them O(n^2) on any
  # source file with a Korean comment or an emoji in a string literal, and at
  # least one carried a comment about materializing `.chars` up front to work
  # around exactly that. A splitter only ever moves forward, so `each_char`
  # plus one `String::Builder` per part is O(n) with no random access at all,
  # no `.chars` array, and no ASCII-vs-UTF-8 dispatch.
  #
  # This is deliberately NOT the `single_byte?` / `Bytes`-vs-`Array(Char)`
  # dispatch used by `Noir::JSLiteralScanner`. That pattern exists there for
  # `find_matching_*`, which must random-access from an arbitrary index and so
  # genuinely needs an indexable source. A forward-only splitter does not, and
  # paying for the dispatch (plus a full `.chars` materialization on non-ASCII
  # input) would be strictly slower than just iterating.
  module TopLevelSplit
    extend self

    # Bracket kinds whose depth suppresses splitting. Callers enable only the
    # kinds their language actually nests: C++ argument lists must count
    # `< >` as comparison operators, not generics, or `f(a < b, c)` loses a
    # part, while a Java generic-signature splitter counts nothing else.
    @[Flags]
    enum Nest
      Paren   # ( )
      Bracket # [ ]
      Brace   # { }
      Angle   # < >
    end

    # How a backslash is treated.
    #
    # `InQuotes` consumes the backslash AND the following character as part of
    # the quoted run, and RETAINS the backslash in the emitted part — verified
    # against the implementations being replaced (e.g. drogon/httplib/oatpp
    # `split_top_level_args`, which append the char first and only then decide
    # whether it was an escape). Callers re-parse the literal themselves, so
    # stripping the backslash here would have silently changed every route
    # string that contained an escaped quote.
    enum Escape
      None     # backslash is an ordinary character, even inside quotes
      InQuotes # backslash escapes the next char only inside a quoted run
      Always   # backslash escapes the next char everywhere
    end

    # What happens to parts that are empty after `strip`.
    enum Empties
      Keep         # every part is emitted, empties included
      DropTrailing # a final empty part is dropped; interior empties survive
      DropAll      # every empty part is dropped
    end

    # The seven axes along which the hand-rolled copies differed.
    struct Rules
      # Bracket kinds that contribute depth.
      getter nest : Nest

      # Characters that open and close a quoted run. A run is closed by the
      # same character that opened it, so `"'"` + `"\""` in one string handles
      # both quote styles without letting `"it's"` open an apostrophe run.
      # `""` disables quote handling entirely.
      getter quotes : String

      # Backslash policy; see `Escape`.
      getter escape : Escape

      # Whether each part is `strip`ped. Applied BEFORE the `Empties` policy,
      # so a whitespace-only part counts as empty.
      getter? strip : Bool

      # Empty-part policy; see `Empties`.
      getter empties : Empties

      # true  => an independent depth counter per bracket kind
      # false => one shared depth across all enabled kinds
      #
      # Configurable rather than fixed because it is observable on UNBALANCED
      # input, which is what these splitters actually receive: every caller
      # hands them a regex-sliced fragment, not a parsed expression. On
      # `"[a)b, c"` a shared counter reads `[` as +1 and `)` as -1 and splits
      # at the comma; per-kind counters leave the bracket depth at 1 and emit
      # one part. Normalizing to either value would have moved endpoints in
      # whichever group lost.
      getter? per_kind : Bool

      # true  => a closer at depth 0 is ignored (`d -= 1 if d > 0`)
      # false => depth is allowed to go negative
      #
      # Same reasoning as `per_kind`. Most replaced sites clamp, but three do
      # a bare `depth -= 1` — erlang/cowboy.cr `split_top_level`,
      # php/wordpress.cr `split_top_level_args`, and engines/cfml_engine.cr
      # `split_arguments` (the last one is easy to miss: it is on the shared
      # engine, not an analyzer, so a survey scoped to `analyzers/` reports
      # only two). On a fragment that closes a bracket opened in a prefix
      # the regex already discarded (e.g. `")x, y"`) that is the difference
      # between one part and two. Splitting requires depth EXACTLY 0, so a
      # negative depth suppresses every remaining split rather than
      # re-enabling them.
      getter? clamp : Bool

      def initialize(
        @nest : Nest = Nest::Paren | Nest::Bracket | Nest::Brace,
        @quotes : String = "\"'",
        @escape : Escape = Escape::InQuotes,
        @strip : Bool = true,
        @empties : Empties = Empties::DropTrailing,
        @per_kind : Bool = false,
        @clamp : Bool = true,
      )
      end

      # C++ call-argument lists.
      # Serves: analyzer/analyzers/cpp/{drogon,httplib,oatpp}.cr
      # `split_top_level_args`. Double quotes only (C++ single quotes are char
      # literals and never wrap a route), per-kind counters and clamping both
      # taken verbatim from those three bodies, `<>` deliberately NOT counted.
      CPP = new(
        nest: Nest::Paren | Nest::Bracket | Nest::Brace,
        quotes: "\"",
        escape: Escape::InQuotes,
        strip: true,
        empties: Empties::DropTrailing,
        per_kind: true,
        clamp: true,
      )

      # Python call-argument lists and expression terms.
      # Serves the six byte-identical `split_python_arguments` clones in
      # analyzer/analyzers/python/{bottle,cherrypy,django,pyramid,sanic,
      # starlette}.cr plus django.cr `split_python_expression_terms` (same
      # body, `+` instead of `,`). Note these deliberately do NOT strip and
      # keep every empty part — callers strip themselves and some index
      # positionally, so an interior empty must hold its slot.
      #
      # Near misses that need their own `Rules` when converted:
      #   flask.cr  `split_python_call_args`  -> Escape::Always, strip: true,
      #                                          Empties::DropAll, and one
      #                                          counter shared by `[`/`{`
      #                                          only — not expressible here.
      PYTHON = new(
        nest: Nest::Paren | Nest::Bracket | Nest::Brace,
        quotes: "\"'",
        escape: Escape::InQuotes,
        strip: false,
        empties: Empties::Keep,
        per_kind: true,
        clamp: true,
      )

      # `PYTHON` with one shared depth counter instead of per-kind counters.
      # Serves analyzer/analyzers/python/{django_ninja,falcon}.cr
      # `split_python_arguments`, fastapi.cr `split_python_top_level` and
      # elixir/elixir_phoenix.cr `split_top_level_commas`.
      #
      # A named preset rather than four inline `Rules.new(...)` literals
      # because the split is not a per-file accident: the Python analyzers
      # genuinely disagree on `per_kind`, and keeping the two variants
      # adjacent is what makes that disagreement — and the fact that it is
      # only observable on unbalanced input — legible. Four copies of the
      # same seven-argument literal in four files is exactly the drift this
      # module exists to end.
      #
      # Named for the shape and not for Python because it turned out not to
      # be a Python idiom at all: Phoenix's splitter, written independently
      # in another language, agrees on all seven axes. It was
      # `PYTHON_SHARED_DEPTH` while Python was its only user.
      SHARED_DEPTH_RAW = new(
        nest: Nest::Paren | Nest::Bracket | Nest::Brace,
        quotes: "\"'",
        escape: Escape::InQuotes,
        strip: false,
        empties: Empties::Keep,
        per_kind: false,
        clamp: true,
      )

      # Java annotation and call-argument lists.
      # Serves four sites in analyzer/analyzers/java/: armeria.cr
      # `split_top_level_args` AND `split_top_level_concat` (same body, `+`
      # instead of `,`), dropwizard.cr `split_top_level_args`, and vertx.cr
      # `split_top_level`, which takes the separator as a parameter and is
      # called with both `,` and `+`. Note dropwizard's copy was written
      # against a `String::Builder` and the other three against index slices;
      # they are nevertheless observably identical, unbalanced input included.
      # One shared depth is unanimous across the Java splitters, unlike Python
      # and JS.
      #
      # Three Java sites each disagree with this preset on one or two axes and
      # so carry a file-local `Rules` constant rather than a preset here — each
      # is used by exactly one splitter, so naming them centrally would put
      # three single-use constants in this file:
      #   quarkus.cr `split_top_level_args`   -> nest also includes Angle
      #   wicket.cr  `split_arguments`        -> nest also includes Angle,
      #                                          quotes "\"" only
      #   spring.cr  `split_top_level_concat` -> quotes "\"", Empties::DropAll
      JAVA = new(
        nest: Nest::Paren | Nest::Bracket | Nest::Brace,
        quotes: "\"'",
        escape: Escape::InQuotes,
        strip: true,
        empties: Empties::DropTrailing,
        per_kind: false,
        clamp: true,
      )

      # JavaScript/TypeScript object-literal and argument lists.
      # Serves analyzer/analyzers/javascript/nestjs.cr and
      # analyzer/analyzers/typescript/loopback.cr `split_top_level`, which are
      # byte-identical and are called with both `,` and `+`. Backticks are
      # quote characters because template literals wrap most route strings;
      # missing them merges a whole `${...}` route into one part.
      #
      # Three more JS/TS sites each disagree on one to four axes and carry a
      # file-local `Rules` constant rather than a preset here, each being the
      # only user of its variant:
      #   typescript/trpc.cr  `split_top_level`        -> per_kind: false
      #   javascript/nextjs.cr `split_top_level_commas` -> no quotes, no
      #                                          escape, nest adds Angle,
      #                                          strip: false, Empties::Keep
      #   javascript/remix.cr `split_flat_segments`    -> Nest::Bracket only,
      #                                          no quotes, strip: false,
      #                                          Empties::Keep, delimiter `.`
      #
      # NOT converted — javascript/express/router_mount_scanner.cr
      # `split_at_top_level_commas` agrees with this preset on every axis
      # except escaping, which it does with `prev_char != '\\'` instead of an
      # escape flag. That misreads `"a\\"` as an unterminated string (the
      # escaped backslash is taken as escaping the closing quote), so no
      # `Escape` value reproduces it and converting would change where it
      # splits. The three `split_top_level_args` copies in
      # javascript/{express,feathers,hono}.cr are likewise left alone: they
      # return `{part, offset}` tuples, and this module returns only strings.
      JS = new(
        nest: Nest::Paren | Nest::Bracket | Nest::Brace,
        quotes: "\"'`",
        escape: Escape::InQuotes,
        strip: true,
        empties: Empties::DropAll,
        per_kind: true,
        clamp: true,
      )

      # Type lists: angle brackets only, no quote handling.
      # Serves the three byte-identical `split_top_level_commas` clones in
      # miniparsers/{java_route,jaxrs,micronaut}_extractor_ts.cr. All three run
      # on the tail of an `implements` clause with the class body already
      # truncated at `{`, so only generic arguments can nest and a stray `"`
      # would swallow the rest of the type list. They keep empties and do not
      # strip; every caller strips each part itself and skips the empties.
      GENERICS_ONLY = new(
        nest: Nest::Angle,
        quotes: "",
        escape: Escape::None,
        strip: false,
        empties: Empties::Keep,
        per_kind: false,
        clamp: true,
      )
    end

    # Splits `text` on every occurrence of `delimiter` that sits at depth 0 and
    # outside a quoted run.
    def split(text : String, delimiter : Char, rules : Rules) : Array(String)
      split_impl(text, [delimiter], rules)
    end

    # Multi-character separator variant. Only a separator run that sits
    # ENTIRELY at depth 0 and outside quotes splits, so `":>"` does not fire on
    # a bare `":"` and `"||"` inside `f(a || b)` is invisible.
    #
    # PRECONDITION: no proper prefix of the delimiter may contain a character
    # that is a quote under `rules`, a backslash, or an opener of an enabled
    # `Nest` kind. Releasing a mismatched prefix character is what changes
    # cursor state, and if that release opens a quote or raises depth the
    # remaining buffered characters stop being top-level and are replayed
    # after the characters that followed them in the source — `split("(((xy",
    # "((x", nest: Paren)` yields `["(xy(("]`, not `["(", "y"]`.
    #
    # Every separator in the tree is punctuation outside all three sets
    # (`","`, `":>"`, `":<|>"`, `"||"`, `"&&"`), so no caller is affected. The
    # note in `Cursor#consume` about a quote-bearing delimiter is the same
    # precondition seen from the other end.
    def split(text : String, delimiter : String, rules : Rules) : Array(String)
      chars = delimiter.chars
      return apply_empties([rules.strip? ? text.strip : text], rules) if chars.empty?
      split_impl(text, chars, rules)
    end

    private def split_impl(text : String, delim : Array(Char), rules : Rules) : Array(String)
      cur = Cursor.new(rules)
      multi = delim.size > 1
      first = delim[0]

      text.each_char do |ch|
        # Inside a quoted run nothing else can happen: no depth change, no
        # split, no new quote. This branch is first because it is also the
        # cheapest, and quoted route strings are where the delimiter character
        # most often appears.
        if quote = cur.quote
          cur.current << ch
          if cur.escaped?
            cur.escaped = false
          elsif ch == '\\' && !rules.escape.none?
            cur.escaped = true
          elsif ch == quote
            cur.quote = nil
          end
          next
        end

        if cur.escaped?
          cur.current << ch
          cur.escaped = false
          next
        end

        if ch == '\\' && rules.escape.always?
          cur.flush_pending
          cur.current << ch
          cur.escaped = true
          next
        end

        if cur.top_level?
          if multi
            # Buffer the run while it is still a prefix of the delimiter. On a
            # mismatch release only the FIRST buffered char and retry the rest,
            # which is what makes `"aab"` findable inside `"aaab"`; releasing
            # the whole buffer would skip past the real match.
            cur.pending << ch
            while (pending = cur.pending).size > 0
              if prefix_of?(pending, delim)
                if pending.size == delim.size
                  pending.clear
                  cur.emit
                end
                break
              end
              cur.consume(pending.shift)
            end
            next
          elsif ch == first
            cur.emit
            next
          end
        end

        cur.consume(ch)
      end

      cur.flush_pending
      cur.emit
      apply_empties(cur.parts, rules)
    end

    private def prefix_of?(buffer : Array(Char), delim : Array(Char)) : Bool
      return false if buffer.size > delim.size
      buffer.each_with_index do |ch, i|
        return false if ch != delim[i]
      end
      true
    end

    private def apply_empties(parts : Array(String), rules : Rules) : Array(String)
      case rules.empties
      in Empties::Keep
        parts
      in Empties::DropTrailing
        parts.pop if !parts.empty? && parts.last.empty?
        parts
      in Empties::DropAll
        parts.reject!(&.empty?)
      end
    end

    # Mutable scan state. A class rather than a bundle of locals so the
    # delimiter-mismatch path can hand a buffered char back to the same
    # ordinary-consumption code the main loop uses, instead of duplicating the
    # depth/quote bookkeeping in two places.
    private class Cursor
      OPENERS = {'(', '[', '{', '<'}

      getter parts = [] of String
      getter pending = [] of Char
      property current = String::Builder.new
      property quote : Char? = nil
      property? escaped = false

      @depths = StaticArray(Int32, 4).new(0)

      def initialize(@rules : Rules)
      end

      # In shared-depth mode only slot 0 is ever touched, so the same all-zero
      # test serves both `per_kind` settings.
      def top_level? : Bool
        @depths[0] == 0 && @depths[1] == 0 && @depths[2] == 0 && @depths[3] == 0
      end

      def emit : Nil
        part = @current.to_s
        part = part.strip if @rules.strip?
        @parts << part
        @current = String::Builder.new
      end

      def flush_pending : Nil
        while (buffered = @pending).size > 0
          consume(buffered.shift)
        end
      end

      def consume(ch : Char) : Nil
        # Only reachable with a quote open when a delimiter containing a quote
        # character stranded a partial match (documented as unsupported); the
        # char still lands verbatim in the part so nothing is lost.
        if @quote
          @current << ch
          return
        end

        if @rules.quotes.includes?(ch)
          @quote = ch
        elsif slot = nest_slot(ch)
          index = @rules.per_kind? ? slot : 0
          if OPENERS.includes?(ch)
            @depths[index] += 1
          elsif @rules.clamp?
            @depths[index] -= 1 if @depths[index] > 0
          else
            @depths[index] -= 1
          end
        end

        @current << ch
      end

      private def nest_slot(ch : Char) : Int32?
        case ch
        when '(', ')' then @rules.nest.paren? ? 0 : nil
        when '[', ']' then @rules.nest.bracket? ? 1 : nil
        when '{', '}' then @rules.nest.brace? ? 2 : nil
        when '<', '>' then @rules.nest.angle? ? 3 : nil
        end
      end
    end
  end
end
