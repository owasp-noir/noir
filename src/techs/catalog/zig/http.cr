# NoirTechs catalog entry: zig_http.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Zig
  HTTP = {
    :zig_http => {
      :framework => "std.http.Server",
      :language  => "Zig",
      :similar   => ["zig-http", "zig_http", "std-http-server", "std.http.server"],
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
