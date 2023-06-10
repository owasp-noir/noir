def detect_ruby_rails(filename : String, file_contents : String)
  check = file_contents.includes?("gem 'rails'")
  check = check || file_contents.includes?("gem \"rails\"")
  check = check && filename.includes?("Gemfile")

  check
end
