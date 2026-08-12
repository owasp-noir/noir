# The ASCII banner, printed to STDERR so `-f json` piped to a file stays
# machine-readable.
module Noir::Banner
  extend self

  def print(io : IO = STDERR)
    # The default art uses extended/box-drawing glyphs that mojibake on a
    # non-UTF-8 Windows console (CP949, …). Ship an ASCII-only variant on
    # Windows so the banner renders cleanly there. Both variants are 11 lines
    # to stay aligned with the `side` text column below.
    # Pre-declare so the macro-branch assignments are visible below.
    art = [] of String
    divider = ""
    {% if flag?(:windows) %}
      art = [
        "          .   |   .          ",
        "       .  |   |   |  .       ",
        "      .   |   |   |   .      ",
        "      |   |   |   |   |      ",
        "          |   |   |          ",
        "    #=====================#  ",
        "          |   |   |          ",
        "      |   |   |   |   |      ",
        "      '   |   |   |   '      ",
        "       '  |   |   |  '       ",
        "          '   |   '          ",
      ]
      divider = "-" * 34
    {% else %}
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
      divider = "─" * 34
    {% end %}

    name = "N O I R".colorize(:white).mode(:bold).to_s
    version = "v#{Noir::VERSION}".colorize(:light_yellow).to_s

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
end
