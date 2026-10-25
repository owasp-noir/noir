module Noir
  # Decides whether a Phoenix/Plug plug can refuse an anonymous caller by
  # reading its definition rather than its name. A module plug is judged by
  # its `call/2`, a function plug (`plug :require_user`) by the `def` of
  # that name in the plugging module or a module it imports; each together
  # with the local helpers it calls and, a few hops deep, the remote helpers
  # it resolves through `alias`es (`H.unauthorized(conn, ...)`).
  #
  # A guard reads who the caller is (a `current_user`-style assign, an
  # authorization/token header, a Guardian/Pow resource) and can refuse:
  # a 401/403, a redirect to a login page, or, for a plug that halts, a
  # 404 that hides the resource. A plug that only loads the user
  # (`AuthPlug` assigning `current_user`) or redirects elsewhere
  # (`RequireLoggedOut` sending users to their dashboard, a first-launch
  # redirect to registration) is not one.
  #
  # ponytail: textual over the reachable function bodies, not path-sensitive;
  # a refusal that fires only for signed-in users (a ban check returning 403)
  # still reads as a guard.
  class ElixirPlugJudge
    record Mod, name : String, path : String, first : Int32, last : Int32

    IDENTITY       = /\bcurrent_(?:user|account|member|resource|scope|identity)\b|get_req_header\([^)]*["'][^"']*(?:auth|token|key|signature)|\bGuardian\.|\bPow\.Plug\b|get_session\([^)]*(?:user|token)/i
    STRONG_REFUSAL = /(?<![\w.])40[13](?![\d.])|:unauthorized\b|:forbidden\b/
    WEAK_REFUSAL   = /(?<![\w.])404(?![\d.])|:not_found\b/
    LOGIN_PATH     = /["'][^"'\n]*\/(?:[\w-]+\/)*(?:log[_-]?in|sign[_-]?in)\b|Routes\.\w*(?:session|login)\w*_path\b/i
    HALT           = /\bhalt\b/
    # Plug's own `Plug.BasicAuth.basic_auth/2` answers 401 and halts.
    BASIC_AUTH = /\bPlug\.BasicAuth\.basic_auth\s*\(|(?<!def )(?<!defp )\bbasic_auth\s*\(\s*conn\b/

    LOCAL_CALL  = /(?<![\w.:@])([a-z_]\w*[!?]?)\s*\(/
    REMOTE_CALL = /(?<![\w.])((?:[A-Z]\w*\.)*[A-Z]\w*)\.([a-z_]\w*[!?]?)\s*\(/

    # Phoenix/Plug function plugs that never refuse a caller.
    BUILTIN_FUNCTION_PLUGS = Set{
      "accepts", "fetch_session", "fetch_flash", "fetch_live_flash",
      "protect_from_forgery", "put_secure_browser_headers", "put_root_layout",
      "put_layout", "put_new_layout", "put_view", "put_new_view",
      "fetch_query_params", "fetch_cookies", "match", "dispatch",
    }

    MAX_FUNCTIONS = 40

    @modules : Hash(String, Mod)?

    def initialize(@files : Array(String), @reader : Proc(String, Array(String)?))
      @clause_cache = Hash({String, String}, Array(String)).new
      @alias_cache = Hash(String, Hash(String, String)).new
      @import_cache = Hash(String, Array(String)).new
      @verdicts = Hash({String, String}, Bool?).new
    end

    # true/false once the definition is read; nil when it is not in the tree.
    def module_plug(ref : String, from_path : String) : Bool?
      return unless mod = resolve_module(ref, from_path)
      memo(mod.name, "call") { verdict(mod, "call", 3, plug: true) }
    end

    def function_plug(name : String, path : String, line_index : Int32) : Bool?
      return false if BUILTIN_FUNCTION_PLUGS.includes?(name)
      return unless mod = function_owner(name, path, line_index)
      memo(mod.name, name) { verdict(mod, name, 3, plug: true) }
    end

    # The action itself refuses: it reads the caller and answers 401/403 or
    # sends them to log in (`with %User{} <- conn.assigns[:current_user]
    # ... else _ -> unauthorized(conn)`). One helper hop deep.
    def action_refuses?(name : String, path : String, line_index : Int32) : Bool
      return false unless mod = enclosing_module(path, line_index)
      !!memo(mod.name, "#{name} action") { verdict(mod, name, 1, plug: false) }
    end

    private def memo(mod : String, func : String, & : -> Bool?) : Bool?
      key = {mod, func}
      return @verdicts[key] if @verdicts.has_key?(key)
      @verdicts[key] = yield
    end

    private def verdict(mod : Mod, func : String, depth : Int32, plug : Bool) : Bool?
      return unless text = closure_text(mod, func, depth)
      return true if plug && text.matches?(BASIC_AUTH)
      return false unless text.matches?(IDENTITY)
      return false if plug && !text.matches?(HALT)
      return true if text.matches?(STRONG_REFUSAL)
      return true if text.includes?("redirect") && text.matches?(LOGIN_PATH)
      plug && text.matches?(WEAK_REFUSAL)
    end

    # The clause bodies of `func` plus the functions they reach, local or
    # remote, up to `depth` calls deep (and MAX_FUNCTIONS in all).
    private def closure_text(mod : Mod, func : String, depth : Int32) : String?
      start = clauses(mod, func)
      return if start.empty?

      seen = Set{ {mod.name, func} }
      queue = [{mod, func, 0}]
      String.build do |io|
        while item = queue.shift?
          current, name, hops = item
          clauses(current, name).each do |body|
            io << body << '\n'
            next if hops >= depth
            body.scan(LOCAL_CALL) do |m|
              callee = m[1]
              next if seen.includes?({current.name, callee}) || seen.size >= MAX_FUNCTIONS
              next if clauses(current, callee).empty?
              seen << {current.name, callee}
              queue << {current, callee, hops + 1}
            end
            body.scan(REMOTE_CALL) do |m|
              next unless target = resolve_module(m[1], current.path)
              next if seen.includes?({target.name, m[2]}) || seen.size >= MAX_FUNCTIONS
              next if clauses(target, m[2]).empty?
              seen << {target.name, m[2]}
              queue << {target, m[2], hops + 1}
            end
          end
        end
      end
    end

    # Every `def`/`defp name` clause in `mod`, as its body text (head through
    # the closing `end`, or the wrapped `, do:` form), comment lines dropped.
    private def clauses(mod : Mod, func : String) : Array(String)
      @clause_cache[{mod.name, func}] ||= begin
        bodies = [] of String
        if lines = @reader.call(mod.path)
          i = mod.first + 1
          while i < mod.last
            line = lines[i]
            stripped = line.lstrip
            if def_head?(stripped, func)
              indent = line.size - stripped.size
              buf = String::Builder.new
              buf << line << '\n'
              j = i + 1
              while j < mod.last
                nxt = lines[j]
                nstripped = nxt.lstrip
                unless nstripped.empty?
                  nindent = nxt.size - nstripped.size
                  if nindent <= indent
                    buf << nxt << '\n' if nstripped.starts_with?("end")
                    break
                  end
                  buf << nxt << '\n' unless nstripped.starts_with?('#')
                end
                j += 1
              end
              bodies << buf.to_s
              i = j
            end
            i += 1
          end
        end
        bodies
      end
    end

    private def def_head?(stripped : String, func : String) : Bool
      rest = if stripped.starts_with?("def ")
               stripped[4..]
             elsif stripped.starts_with?("defp ")
               stripped[5..]
             else
               return false
             end
      return false unless rest.starts_with?(func)
      after = rest[func.size]?
      after.nil? || after == '(' || after == ' ' || after == ','
    end

    private def modules : Hash(String, Mod)
      @modules ||= begin
        index = {} of String => Mod
        @files.each do |path|
          next unless lines = @reader.call(path)
          stack = [] of {Int32, String, Int32}
          lines.each_with_index do |line, i|
            stripped = line.lstrip
            if stripped.starts_with?("defmodule ")
              next unless m = stripped.match(/\Adefmodule\s+([A-Z][\w.]*)\s+do\b/)
              name = (parent = stack.last?) ? "#{parent[1]}.#{m[1]}" : m[1]
              stack << {line.size - stripped.size, name, i}
            elsif stripped.starts_with?("end") && (top = stack.last?) && line.size - stripped.size == top[0]
              stack.pop
              index[top[1]] = Mod.new(top[1], path, top[2], i)
            end
          end
        end
        index
      end
    end

    private def resolve_module(ref : String, from_path : String) : Mod?
      ref = ref.lchop("Elixir.")
      head, _, rest = ref.partition('.')
      if full = aliases(from_path)[head]?
        return modules[rest.empty? ? full : "#{full}.#{rest}"]?
      end
      modules[ref]?
    end

    # `alias A.B.C`, `alias A.B.C, as: X`, `alias A.B.{C, D}` in a file.
    private def aliases(path : String) : Hash(String, String)
      @alias_cache[path] ||= begin
        map = {} of String => String
        (@reader.call(path) || [] of String).each do |line|
          stripped = line.strip
          next unless stripped.starts_with?("alias ")
          if m = stripped.match(/\Aalias\s+([A-Z][\w.]*)\.\{([^}]*)\}/)
            m[2].split(',').each do |part|
              part = part.strip
              map[part.split('.').last] = "#{m[1]}.#{part}" unless part.empty?
            end
          elsif m = stripped.match(/\Aalias\s+([A-Z][\w.]*)(?:\s*,\s*as:\s*([A-Z]\w*))?/)
            map[m[2]? || m[1].split('.').last] = m[1]
          end
        end
        map
      end
    end

    private def imports(path : String) : Array(String)
      @import_cache[path] ||= (@reader.call(path) || [] of String).compact_map do |line|
        line.strip.match(/\Aimport\s+([A-Z][\w.]*)/).try(&.[1])
      end
    end

    private def enclosing_module(path : String, line_index : Int32) : Mod?
      modules.each_value.select { |m| m.path == path && m.first <= line_index && line_index <= m.last }
        .max_by?(&.first)
    end

    private def function_owner(name : String, path : String, line_index : Int32) : Mod?
      if (mod = enclosing_module(path, line_index)) && !clauses(mod, name).empty?
        return mod
      end
      imports(path).each do |ref|
        next unless target = resolve_module(ref, path)
        return target unless clauses(target, name).empty?
      end
      nil
    end
  end
end
