# NoirTechs catalog: perl technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  PERL = {
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
    :perl_catalyst => {
      :framework => "Catalyst",
      :language  => "Perl",
      :similar   => ["catalyst", "perl-catalyst", "perl_catalyst", "catalyst-runtime", "catalyst_runtime"],
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
    },
    :perl_dancer2 => {
      :framework => "Dancer2",
      :language  => "Perl",
      :similar   => ["dancer2", "perl-dancer2", "perl_dancer2"],
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
    },
    :perl_mojolicious => {
      :framework => "Mojolicious",
      :language  => "Perl",
      :similar   => ["mojolicious", "perl-mojolicious", "perl_mojolicious", "mojo"],
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
        :websocket   => true,
      },
    },
  }
end
