def detect_go_echo(filename : String, file_contents : String)
  if (filename.includes? "go.mod") && (file_contents.includes? "github.com/labstack/echo")
    true
  else
    false
  end
end
