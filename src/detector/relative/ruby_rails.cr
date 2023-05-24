def detect_ruby_rails(filename : String, file_contents : String)
  check = false
  check = check || file_contents.include?("require 'rails'")
  check = check || file_contents.include?("require \"rails\"")
  check = check && filename.include?("Gemfile")

  check
end
  