# NoirTechs catalog entry: zig_tokamak.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Zig
  TOKAMAK = {
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
