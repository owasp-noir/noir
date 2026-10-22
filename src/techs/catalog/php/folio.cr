# NoirTechs catalog entry: php_folio.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  FOLIO = {
    :php_folio => {
      :framework => "Laravel Folio",
      :language  => "PHP",
      :similar   => ["folio", "laravel-folio", "php-folio", "php_folio", "laravel/folio"],
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
