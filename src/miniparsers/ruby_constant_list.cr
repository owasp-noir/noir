module Noir
  # Resolves a Ruby list an app keeps behind a class method, as routes and
  # callbacks name it: `Discourse.filters` for
  # `def self.filters; @filters ||= %i[latest unread]; end` in the file that
  # defines `Discourse`. Anything computed resolves to nothing.
  module RubyConstantList
    # `complete` is false when something in the scan extends the list with a
    # value that is not a literal: the values are then a floor, not the list.
    record Result, values : Array(String), complete : Bool

    LITERAL_ITEM = /\A:?["']?(\w+)["']?\z/

    def self.resolve(receiver : String, files : Enumerable(String), & : String -> String?) : Result?
      const_path, _, name = receiver.lchop("::").rpartition('.')
      return if const_path.empty? || name.empty?
      last = const_path.split("::").last
      base = "#{last.underscore}.rb"
      namespaced = "/#{const_path.underscore.gsub("::", "/")}.rb"
      declaration = Regex.new("^\\s*(?:module|class)\\s+(?:\\w+::)*#{Regex.escape(last)}\\b", Regex::Options::MULTILINE)
      definition = Regex.new("^\\s*def\\s+self\\.#{Regex.escape(name)}\\b[^\\n]*\\n(?:\\s*#[^\\n]*\\n)*\\s*(?:@\\w+\\s*\\|\\|=\\s*)?(?:%[wi][\\[\\(\\{]([^\\]\\)\\}]*)[\\]\\)\\}]|\\[([^\\]\\[]*)\\])(?:\\.freeze)?[ \\t]*\\n", Regex::Options::MULTILINE)

      found = [] of Array(String)
      files.each do |file|
        next unless File.basename(file) == base
        # `Admin::Discourse` is `admin/discourse.rb`, not any `discourse.rb`.
        next if const_path.includes?("::") && !file.ends_with?(namespaced)
        next unless (content = yield(file)) && content.matches?(declaration)
        next unless match = content.match(definition)
        items = literal_items(match[1]? || match[2]?, match[1]?.nil?)
        found << items if items
      end
      # Two files defining the constant is a name the scan cannot settle.
      return unless found.size == 1

      values = found.first
      complete = true
      extension = Regex.new("#{Regex.escape(receiver.lchop("::"))}\\s*(?:\\.(?:push|append|unshift|concat)\\(?|<<)\\s*([^\\n]*)")
      files.each do |file|
        next if file.matches?(%r{/(?:spec|test)s?/})
        next unless (content = yield(file)) && content.includes?(receiver.lchop("::"))
        content.scan(extension) do |m|
          added = extension_items(m[1])
          if added && !added.empty?
            added.each { |item| values << item unless values.includes?(item) }
          else
            complete = false
          end
        end
      end
      Result.new(values, complete)
    end

    # `:votes)`, `[:a, :b])`, `%i[a b])`: the literal values an extension adds.
    private def self.extension_items(arg : String) : Array(String)?
      arg = arg.sub(/\s*\)?\s*(?:#.*)?\z/, "").strip
      if m = arg.match(/\A%[wi][\[\(\{]([^\]\)\}]*)[\]\)\}]\z/)
        literal_items(m[1], false)
      elsif m = arg.match(/\A\[([^\]\[]*)\]\z/)
        literal_items(m[1], true)
      else
        literal_items(arg, true)
      end
    end

    private def self.literal_items(text : String?, comma_list : Bool) : Array(String)?
      return unless text
      items = (comma_list ? text.split(',') : text.split(/[\s,]+/)).map(&.strip).reject(&.empty?)
      return if items.empty?
      names = items.compact_map { |item| item.match(LITERAL_ITEM).try(&.[1]) }
      names.size == items.size ? names : nil
    end
  end
end
