# Part of EndpointOptimizer: -P/--set-pvalue rule parsing and application.
class EndpointOptimizer
  private struct PValueRule
    property key : String?
    property value : String

    def initialize(@key : String?, @value : String)
    end
  end

  # Apply parameter values based on configuration. A rule naming the param
  # beats a type-wide default whatever the flag order, so
  # `--pvalue query=1 --pvalue query=limit=10` gives `limit` 10.
  def apply_pvalue(param_type, param_name, param_value) : String
    if rules = @pvalue_rules[param_type]?
      rule = rules.find { |candidate| candidate.key == param_name } || rules.find(&.key.nil?)
      return rule.value if rule
    end

    param_value.to_s
  end

  private PVALUE_TYPES = %w[query json form header cookie path]

  # Per-type rules (`set_pvalue_<type>`) first, then the global `set_pvalue`.
  private def initialize_pvalue_rules : Hash(String, Array(PValueRule))
    global_pvalue = @options["set_pvalue"].as_a
    PVALUE_TYPES.to_h do |type|
      {type, parse_rules(@options["set_pvalue_#{type}"].as_a + global_pvalue)}
    end
  end

  # `key=value` or `key:value`, split on whichever separator comes first;
  # no separator (or a `*` key) applies the value to every param. A `:`
  # opening `://` is a URL value (`https://x/`), not a `key:value` split.
  private def parse_rules(yaml_rules : Array(YAML::Any)) : Array(PValueRule)
    yaml_rules.map do |pvalue|
      pvalue_str = pvalue.to_s
      if separator = pvalue_str.index(/=|:(?!\/\/)/)
        key = pvalue_str[0, separator]
        value = pvalue_str[(separator + 1)..]
      end
      PValueRule.new(key == "*" ? nil : key, value || pvalue_str)
    end
  end
end
