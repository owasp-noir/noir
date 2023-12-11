def banner
  content = <<-CONTENT
░█▄─░█ ░█▀▀▀█ ▀█▀ ░█▀▀█
░█░█░█ ░█──░█ ░█─ ░█▄▄▀
░█──▀█ ░█▄▄▄█ ▄█▄ ░█─░█ {v#{Noir::VERSION}}

CONTENT
  STDERR.puts content
  STDERR.puts ""
end
