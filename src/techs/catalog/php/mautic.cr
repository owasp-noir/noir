# NoirTechs catalog entry: php_mautic.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  MAUTIC = {
    :php_mautic => {
      :framework => "Mautic",
      :language  => "PHP",
      :similar   => ["mautic", "php-mautic", "php_mautic", "mautic/core-lib"],
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
    },
  }
end
