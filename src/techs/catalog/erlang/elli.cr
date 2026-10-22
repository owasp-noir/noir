# NoirTechs catalog entry: erlang_elli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Erlang
  ELLI = {
    :erlang_elli => {
      :framework => "Elli",
      :language  => "Erlang",
      :similar   => ["elli", "erlang-elli", "erlang_elli"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
