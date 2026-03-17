# Parser limits from environment (e.g. for large repos).
#
# NOIR_PARSER_MAX_DEPTH  When set, miniparsers stop following imports beyond this depth.
#                        Depth 0 = entry file only; 1 = entry + direct imports; etc.
#                        Unset or negative = no limit.
module ParserLimit
  extend self

  @@max_depth : Int32? = nil
  @@initialized = false
  @@mutex = Mutex.new

  private def self.init
    return if @@initialized
    @@mutex.synchronize do
      return if @@initialized
      if s = ENV["NOIR_PARSER_MAX_DEPTH"]?
        n = s.to_i?
        # 0 = entry file only (no import following); 1 = entry + direct imports; etc. Negative/unset = no limit.
        @@max_depth = (n && n >= 0) ? n : nil
      end
      @@initialized = true
    end
  end

  # Maximum import depth (0 = entry file only). Nil = no limit.
  def max_depth : Int32?
    init
    @@max_depth
  end

  # Returns true if parsing at the given depth may follow imports (i.e. depth < max_depth).
  def allow_depth?(depth : Int32) : Bool
    init
    max = @@max_depth
    if max.nil?
      true
    else
      depth < max
    end
  end
end
