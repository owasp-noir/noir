def detect_java_spring(filename : String, file_contents : String)
  if (filename.includes? "pom.xml") && (file_contents.includes? "org.springframework")
      true
  else
      false
  end
end
  