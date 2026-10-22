# NoirTechs catalog entry: ts_midway.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Typescript
  MIDWAY = {
    :ts_midway => {
      :framework => "Midway",
      :language  => "TypeScript",
      :similar   => ["midway", "midwayjs", "ts-midway", "ts_midway"],
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
