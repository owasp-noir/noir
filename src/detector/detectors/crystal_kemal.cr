def detect_crystal_kemal(filename : String, file_contents : String)
  check = file_contents.includes?("kemalcr/kemal")
  check = check || file_contents.includes?("dependencies")
  check = check && filename.includes?("shard.yml")

  check
end
