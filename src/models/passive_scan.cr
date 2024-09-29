require "./logger"
require "yaml"

struct PassiveScan
    property id, info, matchers, matchers_condition, category, techs

    def initialize(yaml : YAML::Any)
        @id = yaml["id"].to_s
        @info = yaml["info"]
        @matchers = yaml["matchers"]
        @matchers_condition = yaml["matchers_condition"].to_s
        @category = yaml["category"].to_s
        @techs = yaml["techs"]
    end

    def valid?
        @id != "" && @info != "" && @matchers.size > 0
    end
end