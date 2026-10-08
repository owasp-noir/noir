# NoirTechs catalog entry: python_strawberry.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  STRAWBERRY = {
    :python_strawberry => {
      :framework => "Strawberry GraphQL",
      :language  => "Python",
      :similar   => ["strawberry", "strawberry-graphql", "strawberry_graphql", "python-strawberry", "python_strawberry"],
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
