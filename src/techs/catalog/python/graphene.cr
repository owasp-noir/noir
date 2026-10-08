# NoirTechs catalog entry: python_graphene.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  GRAPHENE = {
    :python_graphene => {
      :framework => "Graphene",
      :language  => "Python",
      :similar   => ["graphene", "graphene-django", "graphene_django", "python-graphene", "python_graphene"],
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
