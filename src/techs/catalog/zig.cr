# NoirTechs catalog: zig technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  ZIG = {
    :zig_cli => {
      :framework => "CLI (zig-cli / zig-clap / std.process / yazap / zig-args)",
      :language  => "Zig",
      :similar   => ["zig-cli", "zig_cli", "clap", "zig-clap", "yazap", "zig-args"],
      :supported => {
        :endpoint => true,
        :method   => false,
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
    },
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
    :zig_tokamak => {
      # Same as Jetzig: Tokamak is built on http.zig and carries its markers.
      :supersedes => ["zig_httpz"],
      :framework  => "Tokamak",
      :language   => "Zig",
      :similar    => ["tokamak", "zig-tokamak", "zig_tokamak"],
      :supported  => {
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
