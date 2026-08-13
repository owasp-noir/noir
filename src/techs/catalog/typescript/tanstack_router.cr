# NoirTechs catalog entry: ts_tanstack_router.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Typescript
  TANSTACK_ROUTER = {
    :ts_tanstack_router => {
      :framework => "TanStack Router",
      :language  => "TypeScript",
      :similar   => ["tanstack-router", "tanstack_router", "ts-tanstack-router", "ts_tanstack_router", "@tanstack/router", "@tanstack/react-router"],
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
        :static_path => true,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
