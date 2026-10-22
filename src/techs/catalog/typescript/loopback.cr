# NoirTechs catalog entry: ts_loopback.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Typescript
  LOOPBACK = {
    :ts_loopback => {
      :framework => "LoopBack",
      :language  => "TypeScript",
      :similar   => ["loopback", "loopback4", "loopback-next", "lb4", "ts-loopback", "ts_loopback"],
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
      :context => {:callee => true, :guards => true},
    },
  }
end
