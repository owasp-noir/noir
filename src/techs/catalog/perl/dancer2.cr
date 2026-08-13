# NoirTechs catalog entry: perl_dancer2.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Perl
  DANCER2 = {
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
      :context => {:callee => true, :guards => true},
    },
  }
end
