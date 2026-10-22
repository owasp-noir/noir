# NoirTechs catalog entry: zig_httpz.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Zig
  HTTPZ = {
    :zig_httpz => {
      :framework => "httpz",
      :language  => "Zig",
      :similar   => ["httpz", "http.zig", "http_zig", "zig-httpz", "zig_httpz"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
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
