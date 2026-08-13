# NoirTechs catalog entry: zig_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Zig
  CLI = {
    :zig_cli => {
      :framework => "CLI (zig-cli / zig-clap / std.process / yazap / zig-args)",
      :language  => "Zig",
      :similar   => ["zig-cli", "zig_cli", "clap", "zig-clap", "yazap", "zig-args"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
