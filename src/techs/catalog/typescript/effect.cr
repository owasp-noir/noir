# NoirTechs catalog entry: ts_effect.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Typescript
  EFFECT = {
    :ts_effect => {
      :framework => "Effect HttpApi",
      :language  => "TypeScript",
      :similar   => ["effect", "effect-httpapi", "ts-effect", "ts_effect", "@effect/platform"],
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
