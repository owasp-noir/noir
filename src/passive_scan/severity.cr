module PassiveScanSeverity
  # Severity levels with their numeric values for comparison
  # Higher numbers indicate more severe issues
  SEVERITY_LEVELS = {
    "critical" => 4,
    "high"     => 3,
    "medium"   => 2,
    "low"      => 1,
  }

  # Check if a given severity meets the minimum threshold
  # @param actual_severity [String] The actual severity of the finding
  # @param min_severity [String] The minimum severity threshold
  # @return [Bool] True if the actual severity meets or exceeds the threshold
  def self.meets_threshold?(actual_severity : String, min_severity : String) : Bool
    actual_level = SEVERITY_LEVELS[actual_severity.downcase]?
    min_level = SEVERITY_LEVELS[min_severity.downcase]?

    # If either severity is unknown, default to including it
    return true if actual_level.nil? || min_level.nil?

    actual_level >= min_level
  end

  # Get the numeric level for a severity string
  # @param severity [String] The severity level
  # @return [Int32] The numeric level, or 0 if unknown
  def self.get_level(severity : String) : Int32
    SEVERITY_LEVELS[severity.downcase]? || 0
  end

  # Check if a severity string is valid
  # @param severity [String] The severity level to validate
  # @return [Bool] True if the severity is valid
  def self.valid?(severity : String) : Bool
    SEVERITY_LEVELS.has_key?(severity.downcase)
  end

  # Get all valid severity levels
  # @return [Array(String)] Array of valid severity level strings
  def self.valid_levels : Array(String)
    SEVERITY_LEVELS.keys
  end
end
