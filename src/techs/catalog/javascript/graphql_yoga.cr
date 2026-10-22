# NoirTechs catalog entry: js_graphql_yoga.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  GRAPHQL_YOGA = {
    :js_graphql_yoga => {
      :framework => "GraphQL Yoga",
      :language  => "JavaScript",
      :similar   => ["graphql-yoga", "graphql_yoga", "yoga", "js-graphql-yoga", "@graphql-yoga/node"],
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
