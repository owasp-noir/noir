class CodeLocator
  @@instance : CodeLocator? = nil

  @logger : NoirLogger
  @is_debug : Bool
  @is_color : Bool
  @is_log : Bool
  @map : Hash(String, String)

  def initialize
    options = {:debug => "true", :color => "true", :nolog => "false"}
    @is_debug = str_to_bool(options[:debug])
    @is_color = str_to_bool(options[:color])
    @is_log = str_to_bool(options[:nolog])
    @logger = NoirLogger.new(@is_debug, @is_color, @is_log)

    @map = Hash(String, String).new
  end

  def self.instance : CodeLocator
    @@instance ||= new
  end

  def set(key : String, value : String)
    @map[key] = value
  end

  def get(key : String) : String
    @map[key]
  rescue
    ""
  end
end
