class CodeLocator
  @@instance : CodeLocator? = nil

  @logger : NoirLogger
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @s_map : Hash(String, String)
  @a_map : Hash(String, Array(String))

  def initialize
    options = {"debug" => "false", "verbose" => "false", "color" => "true", "nolog" => "false"}
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @is_color = any_to_bool(options["color"])
    @is_log = any_to_bool(options["nolog"])
    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log

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

  def show_table
    @logger.sub("String Map:")
    @s_map.each do |key, value|
      @logger.sub("  #{key} => #{value}")
    end
    @logger.sub("Array Map:")
    @a_map.each do |key, value|
      @logger.sub("  #{key} => #{value}")
    end
  end
end
