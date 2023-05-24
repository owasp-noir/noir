def detect_java_jsp(filename : String, file_contents : String)
  check = file_contents.includes?("<%")
  check = check && file_contents.includes?("%>")
  check = check && filename.includes?(".jsp")

  check
end
