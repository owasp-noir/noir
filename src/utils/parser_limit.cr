# Parser limits from environment (e.g. for large repos).
#
# NOIR_PARSER_MAX_DEPTH  When set, miniparsers stop following imports beyond this depth.
#                        Depth 0 = entry file only; 1 = entry + direct imports; etc.
#                        Unset or negative = no limit.
module ParserLimit
  extend self

  # Maximum import depth (0 = entry file only). Nil = no limit.
  def max_depth : Int32?
    ENV["NOIR_PARSER_MAX_DEPTH"]?.try(&.to_i?).try { |n| n if n >= 0 }
  end

  # Returns true if parsing at the given depth may follow imports (i.e. depth < max_depth).
  def allow_depth?(depth : Int32) : Bool
    max = max_depth
    max.nil? || depth < max
  end
end
