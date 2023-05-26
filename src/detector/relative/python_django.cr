def detect_python_django(filename : String, file_contents : String)
  if (filename.includes? ".py") && (file_contents.includes? "from django.")
    true
  else
    false
  end
end
