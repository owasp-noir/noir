# NoirTechs catalog entry: ts_inversify.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Typescript
  INVERSIFY = {
    :ts_inversify => {
      :framework => "inversify-express-utils",
      :language  => "TypeScript",
      :similar   => ["inversify", "inversify-express-utils", "ts-inversify", "ts_inversify"],
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
      :context => {:callee => true},
    },
  }
end
