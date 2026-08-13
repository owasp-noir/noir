# NoirTechs catalog entry: perl_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Perl
  CLI = {
    :perl_cli => {
      :framework => "CLI (Getopt::Long / Getopt::Std / App::Cmd / Getopt::Long::Descriptive / MooX::Options)",
      :language  => "Perl",
      :similar   => ["perl-cli", "perl_cli", "getopt::long", "getopt::std", "app::cmd", "getopt::long::descriptive", "moox::options"],
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
