def remove_start_slash(input_path : String)
  path = input_path
  if path[0].to_s == "/"
    path = remove_start_slash(path[1..-1])
  end

  path
end

def get_relative_path(base_path : String, path : String)
  if base_path[-1].to_s == "/"
    relative_path = path.sub("#{base_path}", "").sub("./", "").sub("//", "/")
  else
    relative_path = path.sub("#{base_path}/", "").sub("./", "").sub("//", "/")
  end
  relative_path = remove_start_slash(relative_path)

  relative_path
end

def join_path(*segments : String) : String
  path = segments.reject(&.empty?).map(&.chomp("/").lstrip("/")).join("/")
  path = "/#{path}" unless path.starts_with?("/")
  path
end

def str_to_bool(str)
  if str == "yes"
    return true
  end

  false
end
