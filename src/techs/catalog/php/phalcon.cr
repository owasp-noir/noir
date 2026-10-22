# NoirTechs catalog entry: php_phalcon.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  PHALCON = {
    :php_phalcon => {
      :framework => "Phalcon",
      :language  => "PHP",
      :similar   => ["phalcon", "cphalcon", "phalcon/cphalcon", "phalcon-framework", "php-phalcon", "php_phalcon", "ext-phalcon"],
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
