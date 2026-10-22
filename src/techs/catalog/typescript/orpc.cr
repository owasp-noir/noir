# NoirTechs catalog entry: ts_orpc.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Typescript
  ORPC = {
    :ts_orpc => {
      :framework => "oRPC",
      :language  => "TypeScript",
      :similar   => ["orpc", "ts-orpc", "ts_orpc", "@orpc/server", "@orpc/contract"],
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
  }
end
