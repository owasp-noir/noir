# NoirTechs catalog entry: erlang_cowboy.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Erlang
  COWBOY = {
    :erlang_cowboy => {
      :framework => "Cowboy",
      :language  => "Erlang",
      :similar   => ["cowboy", "erlang-cowboy", "erlang_cowboy", "cowboy_router"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
