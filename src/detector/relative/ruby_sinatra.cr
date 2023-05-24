def detect_ruby_sinatra(filename : String, file_contents : String)
  check = false
  check = check || file_contents.include?("require 'sinatra'")
  check = check || file_contents.include?("require \"sinatra\"")
  check = check && filename.include?("Gemfile")

  check
end
