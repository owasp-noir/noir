def detect_js_express(filename : String, file_contents : String)
  if (filename.includes? ".js") && (file_contents.includes? "require('express')")
    true
  elsif (filename.includes? ".js") && (file_contents.includes? "require(\"express\")")
    true
  else
    false
  end
end
