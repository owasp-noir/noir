# NoirTechs catalog entry: ruby_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Ruby
  CLI = {
    :ruby_cli => {
      :framework => "CLI (OptionParser / Thor / GLI / Slop / TTY::Option / Optimist / Clamp / dry-cli)",
      :language  => "Ruby",
      :similar   => ["ruby-cli", "ruby_cli", "thor", "optparse", "optionparser", "gli", "slop", "tty-option", "optimist", "clamp", "dry-cli"],
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
