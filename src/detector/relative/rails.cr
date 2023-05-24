def detect_rails(filename : String, file_contents : String)
  if filename.include? "Gemfile" && file_contents.include?("gem 'rails'")
      true
  else
      false
  end
end
  