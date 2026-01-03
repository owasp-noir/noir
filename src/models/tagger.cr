require "./logger"

class Tagger
  @logger : NoirLogger
  @options : Hash(String, YAML::Any)
  @is_debug : Bool
  @is_verbose : Bool
  @is_color : Bool
  @is_log : Bool
  @name : String
  @file_content_cache : Hash(String, String)

  def initialize(options : Hash(String, YAML::Any))
    @is_debug = any_to_bool(options["debug"])
    @is_verbose = any_to_bool(options["verbose"])
    @options = options
    @is_color = any_to_bool(options["color"])
    @is_log = any_to_bool(options["nolog"])
    @name = ""
    @file_content_cache = Hash(String, String).new

    @logger = NoirLogger.new @is_debug, @is_verbose, @is_color, @is_log
  end

  def name
    @name
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    # After inheriting the class, write an action code here.

    endpoints
  end

  # Reads the source code content for a given file path.
  # Results are cached to avoid repeated file reads.
  # Returns nil if the file cannot be read.
  protected def read_source_code(path : String) : String?
    if cached = @file_content_cache[path]?
      return cached
    end

    begin
      content = File.read(path, encoding: "utf-8", invalid: :skip)
      @file_content_cache[path] = content
      content
    rescue
      @logger.debug "Failed to read source file: #{path}"
      nil
    end
  end

  # Reads the source code lines around an endpoint's code path.
  # Returns a tuple of (lines_before, target_line, lines_after) or nil if cannot read.
  # The context_lines parameter controls how many lines before/after to include.
  protected def read_source_context(path_info : PathInfo, context_lines : Int32 = 10) : Tuple(Array(String), String?, Array(String))?
    return nil if path_info.line.nil?

    content = read_source_code(path_info.path)
    return nil if content.nil?

    lines = content.lines
    line_index = path_info.line - 1 # Convert to 0-based index

    return nil if line_index < 0 || line_index >= lines.size

    # Calculate start and end indices for context
    start_index = [0, line_index - context_lines].max
    end_index = [lines.size - 1, line_index + context_lines].min

    lines_before = lines[start_index...line_index]
    target_line = lines[line_index]
    lines_after = lines[(line_index + 1)..end_index]

    {lines_before, target_line, lines_after}
  end

  # Gets all source code content for an endpoint.
  # Returns an array of tuples containing (path_info, content) for each code_path.
  # Note: Code paths where the file cannot be read are filtered out from results.
  # The result array may have fewer elements than endpoint.details.code_paths.
  protected def get_endpoint_source_code(endpoint : Endpoint) : Array(Tuple(PathInfo, String))
    result = [] of Tuple(PathInfo, String)

    endpoint.details.code_paths.each do |path_info|
      content = read_source_code(path_info.path)
      result << {path_info, content} if content
    end

    result
  end

  # Searches for a pattern in the source code around an endpoint's definition.
  # Returns true if the pattern is found in any of the endpoint's source code locations.
  protected def source_contains_pattern?(endpoint : Endpoint, pattern : Regex, context_lines : Int32 = 20) : Bool
    endpoint.details.code_paths.each do |path_info|
      context = read_source_context(path_info, context_lines)
      next if context.nil?

      lines_before, target_line, lines_after = context

      # Check all context lines
      all_lines = lines_before + [target_line].compact + lines_after
      all_lines.each do |line|
        return true if pattern.matches?(line)
      end
    end

    false
  end

  # Extracts matching groups from source code around an endpoint's definition.
  # Returns all matches found in the source code context.
  protected def extract_from_source(endpoint : Endpoint, pattern : Regex, context_lines : Int32 = 20) : Array(Regex::MatchData)
    matches = [] of Regex::MatchData

    endpoint.details.code_paths.each do |path_info|
      context = read_source_context(path_info, context_lines)
      next if context.nil?

      lines_before, target_line, lines_after = context

      # Check all context lines
      all_lines = lines_before + [target_line].compact + lines_after
      all_lines.each do |line|
        if match = pattern.match(line)
          matches << match
        end
      end
    end

    matches
  end
end
