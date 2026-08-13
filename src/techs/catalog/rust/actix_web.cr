# NoirTechs catalog entry: rust_actix_web.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Rust
  ACTIX_WEB = {
    :rust_actix_web => {
      :framework => "Actix Web",
      :language  => "Rust",
      :similar   => ["actix-web", "actix_web", "rust-actix-web", "rust_actix_web"],
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
      :context => {:callee => true, :guards => true},
    },
  }
end
