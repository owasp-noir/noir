# NoirTechs catalog entry: php_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  CLI = {
    :php_cli => {
      :framework => "CLI (symfony/console / getopt / artisan / wp-cli / robo)",
      :language  => "PHP",
      :similar   => ["php-cli", "php_cli", "symfony-console", "getopt", "climate", "minicli", "artisan", "illuminate-console", "wp-cli", "robo"],
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
