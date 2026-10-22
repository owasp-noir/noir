# NoirTechs catalog entry: php_magento.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  MAGENTO = {
    :php_magento => {
      # Same as Drupal: Symfony components underneath, but the routes live in
      # `webapi.xml` / `routes.xml` and only the Magento analyzer reads them.
      :supersedes => ["php_symfony"],
      :framework  => "Magento",
      :language   => "PHP",
      :similar    => ["magento", "magento2", "php-magento", "php_magento", "magento/product-community-edition"],
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
