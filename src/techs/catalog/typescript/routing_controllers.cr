# NoirTechs catalog entry: ts_routing_controllers.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Typescript
  ROUTING_CONTROLLERS = {
    :ts_routing_controllers => {
      :framework => "routing-controllers",
      :language  => "TypeScript",
      :similar   => ["routing-controllers", "routing_controllers", "ts-routing-controllers", "ts_routing_controllers"],
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
