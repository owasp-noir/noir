# NoirTechs catalog entry: perl_mojolicious.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Perl
  MOJOLICIOUS = {
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
      :context => {:callee => true, :guards => true},
    },
  }
end
