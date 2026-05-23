def banner(io : IO = STDERR)
  art = [
    "           ùç  Y  wù           ",
    "        ™w£ Í  ±  Í £w2        ",
    "       ù£   Ï  Ï  Ï   £ù       ",
    "      ù£    Ï  Ï  Ï  ± £ù      ",
    "         Ï  Ï  Ï  Ï  Ï         ",
    "     2YV±ÏÏÏÏÏÏÏÏÏÏÏÏÏ3ÍY2     ",
    "         Ï  Ï  Ï  Ï  Ï         ",
    "      ù£ ±  Ï  Ï  Ï  ± £ç      ",
    "       ù£   Ï  Ï  Ï   £ç       ",
    "        2w£ Í  ±  Í £©2        ",
    "           ùw  Y  wù           ",
  ]

  name = "N O I R".colorize(:white).mode(:bold).to_s
  version = "v#{Noir::VERSION}".colorize(:light_yellow).to_s
  divider = "─" * 34

  side = [
    "",
    "",
    "  #{name}   #{version}",
    "  #{divider.colorize(:dark_gray)}",
    "",
    "  Hunt every Endpoint,".colorize(:white).to_s,
    "  expose Shadow APIs,".colorize(:white).to_s,
    "  map the Attack Surface.".colorize(:white).to_s,
    "",
    "  #{"OWASP · github.com/owasp-noir/noir".colorize(:dark_gray)}",
    "",
  ]

  art_color = Colorize::Color256.new(81)

  io.puts ""
  art.each_with_index do |line, i|
    io.puts "#{line.colorize(art_color)}#{side[i]}"
  end
  io.puts ""
end
