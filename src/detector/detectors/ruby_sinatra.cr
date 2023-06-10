def detect_ruby_sinatra(filename : String, file_contents : String)
  check = file_contents.includes?("gem 'sinatra'")
  check = check || file_contents.includes?("gem \"sinatra\"")
  check = check && filename.includes?("Gemfile")

  check
end
