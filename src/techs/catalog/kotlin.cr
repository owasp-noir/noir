# NoirTechs catalog: kotlin technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  KOTLIN = {
    :kotlin_cli => {
      :framework => "CLI (clikt / kotlinx-cli / picocli)",
      :language  => "Kotlin",
      :similar   => ["kotlin-cli", "kotlin_cli", "clikt", "kotlinx-cli", "picocli"],
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
    :kotlin_http4k => {
      :framework => "http4k",
      :language  => "Kotlin",
      :similar   => ["http4k", "kotlin-http4k", "kotlin_http4k"],
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
    :kotlin_spring => {
      :framework => "Spring",
      :language  => "Kotlin",
      :similar   => ["spring", "kotlin-spring", "kotlin_spring"],
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
      :context => {:callee => true, :guards => true},
    },
    :kotlin_ktor => {
      :framework => "Ktor",
      :language  => "Kotlin",
      :similar   => ["ktor", "kotlin-ktor", "kotlin_ktor"],
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
