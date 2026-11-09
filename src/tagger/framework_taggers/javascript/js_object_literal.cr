require "../../../utils/top_level_split"

# Text-level reads of a JS object literal, shared by the Express and
# misc-JS auth taggers.
module Noir::JSObjectLiteral
  extend self

  # The source text of property `prop` in `{ ... }` (`prop: value`,
  # `'prop': value`), or nil when `object_text` is not an object literal
  # or has no such key.
  def property(object_text : String, prop : String) : String?
    text = object_text.strip
    return unless text.starts_with?('{') && text.ends_with?('}')
    Noir::TopLevelSplit.split(text[1...-1], ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS).each do |part|
      if found = part.match(/\A\s*['"]?#{Regex.escape(prop)}['"]?\s*:\s*(.*)\z/m)
        return found[1].strip
      end
    end
    nil
  end
end
