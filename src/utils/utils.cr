def remove_start_slash(input_path : String)
  path = input_path
  if path[0].to_s == "/"
    path = remove_start_slash(path[1..-1])
  end

  path
end

def str_to_bool(str)
  if str == "yes"
    return true
  end

  false
end
