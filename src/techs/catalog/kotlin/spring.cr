# NoirTechs catalog entry: kotlin_spring.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Kotlin
  SPRING = {
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
  }
end
