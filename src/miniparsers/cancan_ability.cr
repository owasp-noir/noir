module Noir
  # What a CanCanCan `Ability#initialize(user)` grants a caller with no
  # user. The rules are read in order with the `if`/`unless` blocks and
  # modifiers around them; a condition is judged for a nil user: `if
  # user&.active?` never runs, `unless user` always does, an app setting
  # (`Settings.status != "offline"`) is taken as on, and anything else is
  # unknown. `verdict` folds the rules that cover an action the way CanCan
  # does (a later rule wins).
  # ponytail: only the class's own file is read, with the helper methods it
  # defines inlined; an ability that includes other modules, merges another
  # ability or calls a method it does not define is unreadable.
  class CanCanAbility
    enum Grant
      Yes
      No
      Maybe
    end

    # `conditioned`: the rule carries hash or block conditions; `on_user`:
    # those conditions read the caller.
    record Rule, actions : Array(String), subjects : Array(String), grant : Grant, allows : Bool,
      conditioned : Bool = false, on_user : Bool = false

    getter rules = [] of Rule
    getter? readable = true
    @aliases = {"read" => ["index", "show"], "create" => ["new"], "update" => ["edit"]}
    @defs = Hash(String, Int32).new
    @user = "user"
    @guest = false

    def initialize(@lines : Array(String))
      @lines = @lines.map { |line| code_only(line) }
      @lines.each_with_index do |line, idx|
        if m = line.match(/\A\s*def\s+(\w+[!?]?)/)
          @defs[m[1]] = idx
        elsif line.matches?(/\A\s*(?:include|extend|prepend)\s+(?!CanCan::Ability\b)/)
          @readable = false
        end
      end
      unless (init = @defs["initialize"]?) && (param = @lines[init].match(/def\s+initialize\s*\(?\s*(\w+)/))
        @readable = false
        return
      end
      @user = param[1]
      @guest = @lines.any?(&.matches?(/\A\s*#{@user}\s*\|\|=/))
      read_body(init, [] of Grant, 0)
    end

    # `Yes` when a nil user is allowed `action` on `subject`, `No` when
    # every rule that could allow it needs a user, `Maybe` otherwise.
    # `subject` is a class (`Note`) or symbol (`:profile`) name. `instance`:
    # CanCan checks a loaded record, not the class. On a class check it
    # ignores a rule's hash/block conditions: a conditioned `can` allows, a
    # conditioned `cannot` is skipped. On a record, a `can` whose conditions
    # read the caller fails for a nil user (and is unknown for a guest
    # object); a conditioned `cannot` refuses
    # only some records and is skipped. A subject no rule names (`:all`
    # aside) is one this reader may have derived wrongly: `Maybe`.
    def verdict(action : String, subject : String, instance : Bool = false) : Grant
      return Grant::Maybe unless readable?
      return Grant::Maybe unless rules.any?(&.subjects.any? { |name| name == "all" || name == "*" || same_subject?(name, subject) })
      result = Grant::No
      rules.each do |rule|
        next unless covers?(rule.actions, action, 0) && rule.subjects.any? { |name| name == "all" || name == "*" || same_subject?(name, subject) }
        next if rule.conditioned && !rule.allows
        grant = rule.grant
        if rule.conditioned && instance && rule.on_user
          # A guest object (`user ||= User.new`) is compared, not nil:
          # whether a record matches it is the data's to say.
          next unless @guest
          grant = Grant::Maybe unless grant.no?
        end
        polarity = rule.allows ? Grant::Yes : Grant::No
        result = case grant
                 when Grant::Yes then polarity
                 when Grant::No  then result
                 else                 result == polarity ? result : Grant::Maybe
                 end
      end
      result
    end

    private def covers?(actions : Array(String), action : String, depth : Int32) : Bool
      actions.any? do |name|
        name == action || name == "manage" || name == "*" ||
          (depth < 4 && (@aliases[name]?.try { |list| covers?(list, action, depth + 1) } || false))
      end
    end

    # `Issue` matches `issue` / `issues`; a symbol matches its own name.
    private def same_subject?(rule : String, subject : String) : Bool
      return rule == subject if rule.starts_with?(':') || subject.starts_with?(':')
      rule.split("::").last == subject.split("::").last
    end

    private def read_body(def_idx : Int32, outer : Array(Grant), depth : Int32)
      return @readable = false if depth > 4
      def_indent = indent(@lines[def_idx])
      # Each open block: its indent, the grant of the branch being read,
      # and the conditions of the branches before it (for `else`).
      stack = [] of {Int32, Grant, Array(String)}
      tail = [] of Grant         # `return if ...` exits, for the rest of the body
      skip_indent : Int32? = nil # inside a `can ... do |record|` block
      ((def_idx + 1)...@lines.size).each do |idx|
        line = @lines[idx]
        text = line.strip
        next if text.empty?
        ind = indent(line)
        break if ind <= def_indent
        if si = skip_indent
          next if ind > si
          skip_indent = nil
          next if text == "end" && ind == si
        end
        while (top = stack.last?) && top[0] > ind
          stack.pop
        end
        if (top = stack.last?) && top[0] == ind
          case text
          when "end"
            stack.pop
            next
          when /\Aelsif\s+(.+)/
            prior = top[2] + [$~[1]]
            stack[-1] = {ind, all(top[2].map { |c| condition(c, true) } + [condition($~[1], false)]), prior}
            next
          when "else"
            stack[-1] = {ind, all(top[2].map { |c| condition(c, true) }), top[2]}
            next
          when /\Awhen\b/
            stack[-1] = {ind, Grant::Maybe, top[2]}
            next
          else
            stack.pop
          end
        end
        current = outer + stack.map(&.[1]) + tail
        if m = text.match(/\A(if|unless)\s+(.+)\z/)
          stack << {ind, condition(m[2], m[1] == "unless"), [m[2]]}
        elsif text.matches?(/\Acase\b/)
          stack << {ind, Grant::Maybe, [] of String}
        elsif text.matches?(/\A(?:can|cannot)\b/)
          read_rule(text, current)
          skip_indent = ind if text.matches?(/\bdo(?:\s*\|[^|]*\|)?\z/) || text.count('{') > text.count('}')
        elsif text.matches?(/\b(?:do|begin)(?:\s*\|[^|]*\|)?\z/)
          stack << {ind, all(current), [] of String}
        elsif m = text.match(/\Areturn\b(?:.*?\s(if|unless)\s+(.+))?\z/)
          tail << (m[2]? ? condition(m[2], m[1] != "unless") : Grant::No)
        elsif text.in?("end", "rescue", "ensure")
          # a block this reader did not open
        elsif m = text.match(/\Aalias_action\s*\(?\s*(.+?)\s*,\s*(?:to:|:to\s*=>)\s*:(\w+)/)
          (@aliases[m[2]] ||= [] of String).concat(symbols(m[1]))
        elsif text.matches?(/\A#{@user}\s*(?:\|\|)?=/) || text.matches?(/\A@?\w+\s*(?:\|\|)?=(?!=)/)
          # an assignment
        elsif (m = text.match(/\A([a-z_]\w*[!?]?)(?:\s*\(.*?\))?(?:\s+(if|unless)\s+(.+))?\z/)) && (callee = @defs[m[1]]?) && m[1] != "initialize"
          read_body(callee, current + (m[3]? ? [condition(m[3], m[2] == "unless")] : [] of Grant), depth + 1)
        elsif all(current) != Grant::No
          # A statement this reader does not know may add rules.
          @readable = false
        end
      end
    end

    # `can [:read, :create], [Note, :search], user_id: user.id if x`.
    private def read_rule(text : String, current : Array(Grant))
      allows = !text.starts_with?("cannot")
      body = text.sub(/\A(?:cannot|can)\s*\(?\s*/, "")
      grants = current.dup
      if m = body.match(/\A(.+?)\s+(if|unless)\s+(.+)\z/)
        body = m[1]
        grants << condition(m[3], m[2] == "unless")
      end
      args = split_args(body.sub(/\s*(?:do\b.*|\{.*\})\z/, "").rchop(")"))
      actions = symbols(args[0]? || "")
      subjects = subjects_of(args[1]? || "")
      grant = all(grants)
      conditioned = args.size > 2 || body.matches?(/\bdo\b|\{/)
      if actions.empty? || subjects.empty?
        actions = ["*"]
        subjects = ["*"]
        grant = Grant::Maybe if grant == Grant::Yes
      end
      @rules << Rule.new(actions, subjects, grant, allows, conditioned, conditioned && body.matches?(user_ref))
    end

    private def split_args(text : String) : Array(String)
      args = [] of String
      depth = 0
      start = 0
      text.each_char_with_index do |char, i|
        case char
        when '[', '(', '{' then depth += 1
        when ']', ')', '}' then depth -= 1
        when ','
          if depth == 0
            args << text[start...i].strip
            start = i + 1
          end
        end
      end
      args << text[start..].strip
      args.reject(&.empty?)
    end

    private def symbols(text : String) : Array(String)
      text = text.strip
      if m = text.match(/\A%[iw][\[(](.*)[\])]\z/)
        return m[1].split
      end
      return [] of String unless text.matches?(/\A\[?\s*:\w+[!?]?(?:\s*,\s*:\w+[!?]?)*\s*\]?\z/)
      text.scan(/:(\w+[!?]?)/).map(&.[1])
    end

    private def subjects_of(text : String) : Array(String)
      text = text.strip
      inner = text.lchop('[').rchop(']')
      items = inner.split(',').map(&.strip)
      return [] of String unless items.all?(&.matches?(/\A(?:[A-Z][\w:]*|:\w+)\z/))
      items.map { |item| item == ":all" ? "all" : item }
    end

    private def user_ref : Regex
      @user_ref ||= /(?<![\w.@:])#{@user}\b(?!\s*:(?!:))/
    end

    @user_ref : Regex?

    # The grant for a nil user of the branch `condition` guards (its
    # negation when `negate`).
    private def condition(text : String, negate : Bool) : Grant
      text = text.strip.sub(/\s*\bthen\z/, "")
      text = text[1..-2].strip if text.starts_with?('(') && text.ends_with?(')') && balanced?(text[1..-2])
      ors = split_top(text, /\|\||\bor\b/)
      return combine(ors.map { |part| condition(part, negate) }, !negate) if ors.size > 1
      ands = split_top(text, /&&|\band\b/)
      return combine(ands.map { |part| condition(part, negate) }, negate) if ands.size > 1
      if text.starts_with?('!') && !text.starts_with?("!=")
        return condition(text[1..], !negate)
      elsif text.starts_with?("not ")
        return condition(text[4..], !negate)
      end
      atom(text, negate)
    end

    # `any` true: OR of the parts; else AND.
    private def combine(parts : Array(Grant), any : Bool) : Grant
      if any
        return Grant::Yes if parts.includes?(Grant::Yes)
        parts.all?(Grant::No) ? Grant::No : Grant::Maybe
      else
        all(parts)
      end
    end

    private def all(parts : Array(Grant)) : Grant
      return Grant::No if parts.includes?(Grant::No)
      parts.all?(Grant::Yes) ? Grant::Yes : Grant::Maybe
    end

    private def atom(text : String, negate : Bool) : Grant
      u = Regex.escape(@user)
      if text.matches?(user_ref)
        holds = if text.matches?(/\A#{u}(?:\.nil\?|\.blank\?|\.new_record\?|\.guest\?|\.anonymous\?|\s*==\s*nil|\.id\.nil\?)\z/)
                  true
                elsif text.matches?(/\A#{u}(?:\.present\?)?\z/)
                  @guest
                elsif @guest && !text.matches?(/\A#{u}(?:&?\.)\w+\?\z/)
                  nil
                else
                  false
                end
        return Grant::Maybe if holds.nil?
        return (holds != negate) ? Grant::Yes : Grant::No
      end
      # An app setting either way: taken as on in a default install.
      return Grant::Yes if text.matches?(/\A(?:(?:::)?[A-Z]\w*(?:::[A-Z]\w*)*\.[a-z_]\w*[?!]?|ENV\b)/)
      Grant::Maybe
    end

    private def split_top(text : String, sep : Regex) : Array(String)
      parts = [] of String
      depth = 0
      start = 0
      i = 0
      while i < text.size
        char = text[i]
        if char.in?('(', '[', '{')
          depth += 1
        elsif char.in?(')', ']', '}')
          depth -= 1
        elsif depth == 0 && (m = text.match(sep, i)) && m.begin == i
          parts << text[start...i].strip
          i = m.end
          start = i
          next
        end
        i += 1
      end
      parts << text[start..].strip
      parts
    end

    private def balanced?(text : String) : Bool
      depth = 0
      text.each_char do |char|
        depth += 1 if char == '('
        depth -= 1 if char == ')'
        return false if depth < 0
      end
      depth == 0
    end

    private def indent(line : String) : Int32
      line.size - line.lstrip.size
    end

    private def code_only(line : String) : String
      line.gsub(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/, %("")).sub(/(?:\A|\s)#(?!\{).*\z/, "")
    end
  end
end
