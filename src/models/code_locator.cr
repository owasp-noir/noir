class CodeLocator
  @@instance : CodeLocator? = nil

  @logger : NoirLogger
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @s_map : Hash(String, String)
  @a_map : Hash(String, Array(String))
  @file_usage_stats : Hash(String, Int32) # Track number of file reads

  def initialize
    options = {"debug" => "false", "verbose" => "false", "color" => "true", "nolog" => "false"}
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @is_color = any_to_bool(options["color"])
    @is_log = any_to_bool(options["nolog"])
    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log

    @s_map = Hash(String, String).new
    @a_map = Hash(String, Array(String)).new
    @file_usage_stats = Hash(String, Int32).new
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

    # Track file usage if this is the file_map
    if key == "file_map"
      increment_file_usage(value)
    end
  end

  def all(key : String) : Array(String)
    result = @a_map[key]?
    return result if result
    Array(String).new
  end

  def clear(key : String)
    @s_map.delete(key)
    @a_map.delete(key)
  end

  def clear_all
    @s_map.clear
    @a_map.clear
    @file_usage_stats.clear
  end

  def show_table
    @logger.sub("String Map:")
    @s_map.each do |key, value|
      @logger.sub("  #{key} => #{value}")
    end
    @logger.sub("Array Map:")
    @a_map.each do |key, value|
      @logger.sub("  #{key} => #{value.size} items")
    end
  end

  # Get file usage statistics
  def file_usage_stats : Hash(String, Int32)
    @file_usage_stats
  end

  # Increment file usage count
  private def increment_file_usage(file_path : String)
    @file_usage_stats[file_path] ||= 0
    @file_usage_stats[file_path] += 1
  end

  # Show file usage statistics
  def show_file_stats
    @logger.sub("File Usage Statistics:")
    @logger.sub("  Total unique files: #{@file_usage_stats.size}")
    total_usages = @file_usage_stats.values.sum
    @logger.sub("  Total file reads: #{total_usages}")

    if @is_verbose && @file_usage_stats.size > 0
      @logger.sub("  Top 10 most accessed files:")
      @file_usage_stats.to_a.sort_by { |_, count| -count }[0..9].each do |file, count|
        @logger.sub("    #{count} times: #{file}")
      end
    end
  end
end
