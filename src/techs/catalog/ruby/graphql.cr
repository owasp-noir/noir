# NoirTechs catalog entry: ruby_graphql.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Ruby
  GRAPHQL = {
    :ruby_graphql => {
      :framework => "GraphQL Ruby",
      :language  => "Ruby",
      :similar   => ["graphql-ruby", "graphql_ruby", "ruby-graphql"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => true,
      },
    },
  }
end
