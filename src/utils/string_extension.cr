class String
  def gsub_repeatedly(pattern, replacement)
    result = self
    if pattern != ""
      while result.includes?(pattern)
        result = result.gsub(pattern, replacement)
      end
    end
    result
  end
end
