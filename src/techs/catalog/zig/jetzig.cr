# NoirTechs catalog entry: zig_jetzig.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Zig
  JETZIG = {
    :zig_jetzig => {
      # Jetzig is built on http.zig, so a project vendoring it also carries the
      # `@import("httpz")` / `.httpz` markers the httpz detector keys on. The
      # framework owns the routing DSL; dropping httpz also stops its analyzer
      # scanning the framework's own internals.
      :supersedes => ["zig_httpz"],
      :framework  => "Jetzig",
      :language   => "Zig",
      :similar    => ["jetzig", "zig-jetzig", "zig_jetzig"],
      :supported  => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
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
