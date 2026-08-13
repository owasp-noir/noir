# NoirTechs catalog entry: scala_akka.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Scala
  AKKA = {
    :scala_akka => {
      :framework => "Akka HTTP",
      :language  => "Scala",
      :similar   => ["akka", "akka-http", "akka_http", "scala-akka", "scala_akka"],
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
      :context => {:callee => true, :guards => true},
    },
  }
end
