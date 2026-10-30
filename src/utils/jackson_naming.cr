module Noir
  # Jackson property naming strategies: a class-level
  # `@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)` or the
  # Spring Boot default `spring.jackson.property-naming-strategy: SNAKE_CASE`
  # renames every JSON key that has no explicit `@JsonProperty`.
  module JacksonNaming
    extend self

    KNOWN = Set{"snakecase", "uppersnakecase", "kebabcase", "lowercase", "lowerdotcase", "uppercamelcase", "lowercamelcase"}

    # `@JsonNaming(X.class)` (Java) / `@JsonNaming(X::class)` (Kotlin).
    ANNOTATION_RE = /@(?:\w+\.)*JsonNaming\s*\(\s*(?:value\s*=\s*)?([\w.]+?)\s*(?:::|\.)\s*class\b/

    # Normalised strategy for a class name (`SnakeCaseStrategy`,
    # `PropertyNamingStrategies.KebabCaseStrategy`) or property value
    # (`SNAKE_CASE`, `com.fasterxml...PropertyNamingStrategies$SnakeCaseStrategy`),
    # nil when it is not a known strategy.
    def strategy(raw : String) : String?
      key = raw.strip.split(/[.$]/).last.sub(/Strategy\z/, "").delete('_').downcase
      KNOWN.includes?(key) ? key : nil
    end

    def annotation_strategy(text : String) : String?
      text.match(ANNOTATION_RE).try { |match| strategy(match[1]) }
    end

    # `@JsonRootName("user")`: the key a body is wrapped in when
    # `UNWRAP_ROOT_VALUE` is on. Nil when absent or empty.
    ROOT_NAME_RE  = /@(?:\w+\.)*JsonRootName\s*\(([^)]*)\)/
    ROOT_VALUE_RE = /(?:\A|,)\s*(?:value\s*=\s*)?"([^"\\]*)"/

    # `@JsonRootName("user")`, `@JsonRootName(namespace = "ns", value = "user")`.
    def annotation_root_name(text : String) : String?
      args = text.match(ROOT_NAME_RE).try(&.[1]) || return
      args.match(ROOT_VALUE_RE).try(&.[1].presence)
    end

    # `spring.jackson.deserialization.UNWRAP_ROOT_VALUE=true`, in any of
    # Spring's relaxed spellings (`unwrap-root-value`).
    def unwrap_root_value?(config : Hash(String, String)) : Bool
      config.any? do |key, value|
        key.downcase.delete("-_") == "spring.jackson.deserialization.unwraprootvalue" && value.strip.downcase == "true"
      end
    end

    def translate(name : String, strategy : String) : String
      case strategy
      when "snakecase"      then snake(name)
      when "uppersnakecase" then snake(name).upcase
      when "kebabcase"      then separated(name, '-')
      when "lowerdotcase"   then separated(name, '.')
      when "lowercase"      then name.downcase
      when "uppercamelcase" then name.empty? ? name : name[0].upcase + name[1..]
      else                       name
      end
    end

    # Jackson's `SnakeCaseStrategy`: `_` before each run of capitals, then
    # lower case (`userURLValue` -> `user_urlvalue`).
    private def snake(name : String) : String
      String.build do |io|
        last = '\0'
        prev_translated = false
        name.each_char do |char|
          if char.uppercase?
            io << '_' if !prev_translated && last != '\0' && last != '_'
            char = char.downcase
            prev_translated = true
          else
            prev_translated = false
          end
          io << char
          last = char
        end
      end
    end

    # Jackson's `NamingBase.translateLowerCaseWithSeparator` (kebab, lower
    # dot): the last capital of an acronym starts the next word
    # (`userURLValue` -> `user-url-value`).
    private def separated(name : String, separator : Char) : String
      chars = [] of Char
      upper_count = 0
      name.each_char_with_index do |char, index|
        lower = char.downcase
        if lower == char
          chars.insert(chars.size - 1, separator) if upper_count > 1
          upper_count = 0
        else
          chars << separator if upper_count.zero? && index > 0
          upper_count += 1
        end
        chars << lower
      end
      chars.join
    end
  end
end
