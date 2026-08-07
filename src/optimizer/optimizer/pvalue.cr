# Part of EndpointOptimizer: -P/--set-pvalue rule parsing and application.
class EndpointOptimizer
  private struct PValueRule
    property key : String?
    property value : String

    def initialize(@key : String?, @value : String)
    end
  end

  # Apply parameter values based on configuration
  def apply_pvalue(param_type, param_name, param_value) : String
    if rules = @pvalue_rules[param_type]?
      rules.each do |rule|
        if rule.key.nil? || rule.key == param_name
          return rule.value
        end
      end
    end

    param_value.to_s
  end

  private def initialize_pvalue_rules : Hash(String, Array(PValueRule))
    rules = Hash(String, Array(PValueRule)).new
    param_types = ["query", "json", "form", "header", "cookie", "path"]
    global_pvalue = @options["set_pvalue"].as_a

    param_types.each do |type|
      pvalue_target = case type
                      when "query"  then @options["set_pvalue_query"]
                      when "json"   then @options["set_pvalue_json"]
                      when "form"   then @options["set_pvalue_form"]
                      when "header" then @options["set_pvalue_header"]
                      when "cookie" then @options["set_pvalue_cookie"]
                      when "path"   then @options["set_pvalue_path"]
                      else               YAML::Any.new([] of YAML::Any)
                      end

      merged_pvalue_target = [] of YAML::Any
      merged_pvalue_target.concat(pvalue_target.as_a)
      merged_pvalue_target.concat(global_pvalue)

      rules[type] = parse_rules(merged_pvalue_target)
    end

    rules
  end

  private def parse_rules(yaml_rules : Array(YAML::Any)) : Array(PValueRule)
    parsed_rules = [] of PValueRule
    yaml_rules.each do |pvalue|
      pvalue_str = pvalue.to_s
      key = nil
      value = pvalue_str

      if pvalue_str.includes?("=") || pvalue_str.includes?(":")
        first_equal = pvalue_str.index("=")
        first_colon = pvalue_str.index(":")

        if first_equal && (!first_colon || first_equal < first_colon)
          split = pvalue_str.split("=", 2)
          key = split[0]
          value = split[1]
        elsif first_colon
          split = pvalue_str.split(":", 2)
          key = split[0]
          value = split[1]
        end
      end

      if key == "*"
        key = nil
      end

      parsed_rules << PValueRule.new(key, value)
    end
    parsed_rules
  end
end
