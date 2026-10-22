# NoirTechs catalog entry: ts_trpc.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Typescript
  TRPC = {
    :ts_trpc => {
      :framework => "tRPC",
      :language  => "TypeScript",
      :similar   => ["trpc", "ts-trpc", "ts_trpc", "@trpc/server", "@trpc/next"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => true,
        :websocket   => true,
      },
      :context => {:callee => true},
    },
  }
end
