# NoirTechs catalog entry: php_drupal.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  DRUPAL = {
    :php_drupal => {
      # Drupal is built on Symfony components, so its composer.json pulls in
      # `symfony/*` and the Symfony detector fires on every Drupal project.
      # Drupal exposes no Symfony-native routes (it uses `*.routing.yml`), and
      # the Symfony YAML analyzer would otherwise double-parse Drupal routing
      # files that happen to sit under a `config` path.
      :supersedes => ["php_symfony"],
      :framework  => "Drupal",
      :language   => "PHP",
      :similar    => ["drupal", "php-drupal", "php_drupal", "drupal/core"],
      :supported  => {
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
