# NoirTechs catalog entry: zig_zap.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Zig
  ZAP = {
    :zig_zap => {
      :framework => "Zap",
      :language  => "Zig",
      :similar   => ["zap", "zigzap", "zig-zap", "zig_zap"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
