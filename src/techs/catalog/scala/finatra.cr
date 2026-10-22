# NoirTechs catalog entry: scala_finatra.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Scala
  FINATRA = {
    :scala_finatra => {
      :framework => "Finatra",
      :language  => "Scala",
      :similar   => ["finatra", "scala-finatra", "scala_finatra"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
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
