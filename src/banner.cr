def banner
  content = <<-CONTENT
░█▄─░█ ░█▀▀▀█ ▀█▀ ░█▀▀█
░█░█░█ ░█──░█ ░█─ ░█▄▄▀
░█──▀█ ░█▄▄▄█ ▄█▄ ░█─░█ {v#{Noir::VERSION}}

CONTENT
  STDERR.puts ""
  STDERR.puts content
  STDERR.puts ""
end
