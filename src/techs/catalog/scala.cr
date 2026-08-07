# NoirTechs catalog: scala technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  SCALA = {
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
    },
    :scala_http4s => {
      :framework => "http4s",
      :language  => "Scala",
      :similar   => ["http4s", "scala-http4s", "scala_http4s"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
    :scala_scalatra => {
      :framework => "Scalatra",
      :language  => "Scala",
      :similar   => ["scalatra", "scala-scalatra", "scala_scalatra"],
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
    :scala_play => {
      :framework => "Play Framework",
      :language  => "Scala",
      :similar   => ["play", "play-framework", "scala-play", "scala_play"],
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
    :scala_tapir => {
      :framework => "Tapir",
      :language  => "Scala",
      :similar   => ["tapir", "sttp-tapir", "sttp_tapir", "scala-tapir", "scala_tapir"],
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
    },
  }
end
