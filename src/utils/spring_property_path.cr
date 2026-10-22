# Resolves Spring `${property:default}` placeholders in any mapping path.
# Nested placeholders are resolved from the inside out, matching Spring's
# PropertySourcesPlaceholderConfigurer behaviour at a best-effort level.
module SpringPropertyPath
  extend self

  def resolve(path : String, properties : Hash(String, String) = {} of String => String) : String
    return path unless path.includes?("${")

    result = path
    100.times do
      match = result.match(/\$\{([^{}]+)\}/)
      break unless match

      expression = match[1]
      colon_idx = expression.index(':')
      property_key, default_value = if colon_idx
                                      {expression[0...colon_idx], expression[colon_idx + 1..-1]}
                                    else
                                      {expression, ""}
                                    end

      value = properties[property_key]? || default_value
      result = result.sub("${#{expression}}", value)
    end

    result
  end
end
