# NoirTechs catalog entry: ts_encore.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Typescript
  ENCORE = {
    :ts_encore => {
      :framework => "Encore",
      :language  => "TypeScript",
      :similar   => ["encore.ts", "ts-encore", "ts_encore"],
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
        :websocket   => true,
      },
    },
  }
end
