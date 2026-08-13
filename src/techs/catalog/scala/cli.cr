# NoirTechs catalog entry: scala_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Scala
  CLI = {
    :scala_cli => {
      :framework => "CLI (scopt / decline / mainargs / scallop / twitter-util)",
      :language  => "Scala",
      :similar   => ["scala-cli", "scala_cli", "scopt", "decline", "mainargs", "scallop", "twitter-util", "util-app"],
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
  }
end
