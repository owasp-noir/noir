# NoirTechs catalog entry: lua_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Lua
  CLI = {
    :lua_cli => {
      :framework => "CLI (argparse / lua_cliargs)",
      :language  => "Lua",
      :similar   => ["lua-cli", "lua_cli", "argparse", "cliargs", "lua_cliargs"],
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
