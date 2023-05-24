def detect_go_echo(filename : String, file_contents : String)
  if filename.include? "go.mod" && file_contents.include?("github.com/labstack/echo")
      true
  else
      false
  end
end
  