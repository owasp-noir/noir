# NoirTechs catalog: erlang technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  ERLANG = {
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
