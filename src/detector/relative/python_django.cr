def detect_python_django(filename : String, file_contents : String)
  if filename.include? ".py" && file_contents.include?("from django.")
      true
  else
      false
  end
end
  