class CodeLocator
  @@instance : CodeLocator? = nil

  @logger : NoirLogger
  @is_debug : Bool
  @is_color : Bool
  @is_log : Bool
  @s_map : Hash(String, String)
  @a_map : Hash(String, Array(String))

  def initialize
    options = {:debug => "true", :color => "true", :nolog => "false"}
    @is_debug = str_to_bool(options[:debug])
    @is_color = str_to_bool(options[:color])
    @is_log = str_to_bool(options[:nolog])
    @logger = NoirLogger.new(@is_debug, @is_color, @is_log)

    @s_map = Hash(String, String).new
    @a_map = Hash(String, Array(String)).new
  end

  def self.instance : CodeLocator
    @@instance ||= new
  end

  def set(key : String, value : String)
    @s_map[key] = value
  end

  def get(key : String) : (String | Array(String))
    @s_map[key]
  rescue
    ""
  end

  def push(key : String, value : String)
    @a_map[key] ||= Array(String).new
    @a_map[key] << value
  end

  def all(key : String) : Array(String)
    @a_map[key]
  rescue
    Array(String).new
  end

  def clear(key : String)
    @s_map.delete(key)
    @a_map.delete(key)
  end

  def clear_all
    @s_map.clear
    @a_map.clear
  end
end
