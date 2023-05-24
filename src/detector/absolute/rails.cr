def detect_absolute_rails(base_path : String)
  check = false
  check = check && File.exists?("#{base_path}/Gemfile")
  check = check && File.exists?("#{base_path}/config.ru")
  check = check && File.exists?("#{base_path}/config/routes.rb")

  check
end
