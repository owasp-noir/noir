class String
  def gsub_repeatedly(pattern, replacement)
    result = self
    while result.includes?(pattern)
      result = result.gsub(pattern, replacement)
    end
    result
  end
end
