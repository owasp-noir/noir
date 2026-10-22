# NoirTechs catalog entry: ts_tsrest.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Typescript
  TS_REST = {
    :ts_tsrest => {
      :framework => "ts-rest",
      :language  => "TypeScript",
      :similar   => ["ts-rest", "tsrest", "ts_rest", "@ts-rest/core"],
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
