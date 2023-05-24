def detect_php_pure(filename : String, file_contents : String)
  check = file_contents.includes?("<?")
  check = check && file_contents.includes?("?>")
  check = check && filename.includes?(".php")

  check
end
