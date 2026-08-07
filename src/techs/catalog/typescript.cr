# NoirTechs catalog: typescript technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  TYPESCRIPT = {
    :ts_nestjs => {
      :framework => "NestJS",
      :language  => "TypeScript",
      :similar   => ["typescript-nestjs", "ts-nestjs", "ts_nestjs"],
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
      :context => {:callee => true, :guards => true},
    },
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
