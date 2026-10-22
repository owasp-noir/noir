# NoirTechs catalog entry: kotlin_http4k.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Kotlin
  HTTP4K = {
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
  }
end
