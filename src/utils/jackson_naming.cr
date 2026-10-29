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

    def translate(name : String, strategy : String) : String
      case strategy
      when "snakecase"      then separated(name, '_')
      when "uppersnakecase" then separated(name, '_').upcase
      when "kebabcase"      then separated(name, '-')
      when "lowerdotcase"   then separated(name, '.')
      when "lowercase"      then name.downcase
      when "uppercamelcase" then name.empty? ? name : name[0].upcase + name[1..]
      else                       name
      end
    end

    # Jackson's `NamingBase.translateLowerCaseWithSeparator`: a separator
    # before each run of capitals, then lower case (`userURL` -> `user_url`).
    private def separated(name : String, separator : Char) : String
      String.build do |io|
        last = '\0'
        prev_translated = false
        name.each_char do |char|
          if char.uppercase?
            io << separator if !prev_translated && last != '\0' && last != separator
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
  end
end
