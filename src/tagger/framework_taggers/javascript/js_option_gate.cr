require "../../../utils/top_level_split"

# How a helper's refusal depends on what its caller passes. umami's
# `parseRequest(request, schema, options?)` refuses under
# `if (!options?.skipAuth && !error)`; whether a given call is refused
# depends on that call's third argument. Every `if` still open around the
# refusal is read for references to the helper's own parameters, and each
# reference becomes a `Gate`: the refusal runs only when that argument (or
# its key) has the value `runs_when`. A local (`!error`) is not a parameter
# and is not read.
module Noir::JSOptionGate
  extend self

  # `index` is the parameter's position, `key` the option key read off it
  # (nil for a bare positional parameter), `absent` the value it has when the
  # call leaves it out (`{ skipAuth = false } = {}`: false), `unknown` a
  # comparison with something other than `true`/`false`.
  record Gate, index : Int32, key : String?, runs_when : Bool, absent : Bool, unknown : Bool

  # A parameter: a name, or the keys of a destructured object, each mapped
  # local name => {key passed, value when absent}.
  record Param, index : Int32, name : String?, keys : Hash(String, Tuple(String, Bool)), absent : Bool

  # The request and its peers: a branch on them depends on the caller, not on
  # an option the route chose.
  REQUEST_PARAM = /\A(?:req|request|res|response|ctx|context|event|headers)\z/
  IDENT         = /\A[A-Za-z_$][\w$]*\z/
  ENTRY         = /\A(?:\.\.\.)?([A-Za-z_$][\w$]*)(?:\s*:\s*([A-Za-z_$][\w$]*))?(?:\s*=\s*([\s\S]+))?\z/
  FALSY         = Set{"false", "null", "undefined", "0", "''", %("")}

  # The parameters of `list`, the text between a function's parentheses.
  def params(list : String) : Array(Param)
    split(list).map_with_index do |raw, idx|
      text = raw.strip
      keys = {} of String => Tuple(String, Bool)
      if text.starts_with?('{') && (close = closing_brace(text))
        split(text[1...close]).each do |entry|
          next unless m = entry.strip.match(ENTRY)
          keys[m[2]? || m[1]] = {m[1], m[3]?.try(&.strip) == "true"}
        end
        Param.new(idx, nil, keys, false)
      else
        name = text.match(/\A(?:\.\.\.)?([A-Za-z_$][\w$]*)/).try(&.[1])
        Param.new(idx, name, keys, text.matches?(/=\s*true\s*\z/))
      end
    end
  end

  # The gates the `if` conditions `conditions` put on a refusal.
  def gates(conditions : Array(String), params : Array(Param)) : Array(Gate)
    gates = [] of Gate
    conditions.each do |cond|
      params.each do |param|
        if name = param.name
          next if name.matches?(REQUEST_PARAM)
          cond.scan(/(!\s*)?(?<![\w$.])#{Regex.escape(name)}\b(?:\s*\??\.\s*([A-Za-z_$][\w$]*))?(\s*[!=]==?\s*[^\s&|)]+)?/) do |m|
            gates << gate(param.index, m[2]?, m[1]?, m[3]?, m[2]? ? false : param.absent)
          end
        else
          param.keys.each do |local, (key, absent)|
            cond.scan(/(!\s*)?(?<![\w$.])#{Regex.escape(local)}\b(?!\s*\??\.)(\s*[!=]==?\s*[^\s&|)]+)?/) do |m|
              gates << gate(param.index, key, m[1]?, m[2]?, absent)
            end
          end
        end
      end
    end
    gates
  end

  # `:skipped` when the call's `args` turn the refusal off, `:unknown` when a
  # value it depends on is not a literal (`{ skipAuth: isPublic }`), `:runs`
  # otherwise. `lookup` gives a `const`'s initializer in the caller.
  # ponytail: the conditions are read as one conjunction; an `||` between
  # an option and something else is judged as if it were `&&`.
  def outcome(gates : Array(Gate), args : Array(String), lookup : Proc(String, String?)) : Symbol
    unknown = false
    gates.each do |gate|
      value = gate.unknown ? nil : value_of(args[gate.index]?, gate.key, gate.absent, lookup)
      if value.nil?
        unknown = true
      elsif value != gate.runs_when
        return :skipped
      end
    end
    unknown ? :unknown : :runs
  end

  private def gate(index : Int32, key : String?, negated : String?, compare : String?, absent : Bool) : Gate
    runs_when = negated.nil?
    unknown = false
    if compare && (m = compare.match(/([!=])==?\s*(\S+)/))
      case m[2]
      when "true"  then runs_when = !runs_when if m[1] == "!"
      when "false" then runs_when = !runs_when if m[1] == "="
      else              unknown = true
      end
    end
    Gate.new(index, key, runs_when, absent, unknown)
  end

  private def value_of(arg : String?, key : String?, absent : Bool, lookup : Proc(String, String?)) : Bool?
    text = arg.try(&.strip) || ""
    return absent if text.empty? || text == "{}" || text == "undefined" || text == "null"
    text = (lookup.call(text) || return).strip if text.matches?(IDENT) && text != "true" && text != "false"
    unless key
      return true if text == "true"
      return false if FALSY.includes?(text)
      return
    end
    return unless text.starts_with?('{')
    if m = text.match(/(?<![\w$.])#{Regex.escape(key)}\s*:\s*([^,}\n]+)/)
      value = m[1].strip
      return true if value == "true"
      return false if FALSY.includes?(value)
      return
    end
    # `{ skipAuth }`, `{ ...opts }`: set, to something not written here.
    return if text.includes?("...") || text.matches?(/(?<![\w$.])#{Regex.escape(key)}\b/)
    absent
  end

  private def split(text : String) : Array(String)
    Noir::TopLevelSplit.split(text, ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).reject(&.strip.empty?)
  end

  private def closing_brace(text : String) : Int32?
    depth = 0
    text.each_char_with_index do |char, idx|
      depth += 1 if char == '{'
      if char == '}'
        depth -= 1
        return idx if depth == 0
      end
    end
    nil
  end
end
