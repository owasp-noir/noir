# NoirTechs catalog entry: scala_zio_http.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Scala
  ZIO_HTTP = {
    :scala_zio_http => {
      :framework => "ZIO HTTP",
      :language  => "Scala",
      :similar   => ["zio", "zio-http", "zio_http", "scala-zio-http", "scala_zio_http"],
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
      :context => {:callee => true},
    },
  }
end
