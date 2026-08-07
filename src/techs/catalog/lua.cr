# NoirTechs catalog: lua technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  LUA = {
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
    :lua_lapis => {
      :framework => "Lapis",
      :language  => "Lua",
      :similar   => ["lapis", "lua-lapis", "lua_lapis"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
    :lua_lor => {
      :framework => "lor",
      :language  => "Lua",
      :similar   => ["lor", "lua-lor", "lua_lor"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
