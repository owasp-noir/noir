# NoirTechs catalog entry: rust_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Rust
  CLI = {
    :rust_cli => {
      :framework => "CLI (std::env / clap / structopt / argh / getopts)",
      :language  => "Rust",
      :similar   => ["rust-cli", "rust_cli", "clap", "structopt", "argh", "bpaf", "pico-args", "getopts"],
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
  }
end
