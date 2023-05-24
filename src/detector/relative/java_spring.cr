def detect_java_spring(filename : String, file_contents : String)
  if filename.include? "pom.xml" && file_contents.include?("org.springframework")
      true
  else
      false
  end
end
  