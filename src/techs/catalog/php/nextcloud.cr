# NoirTechs catalog entry: php_nextcloud.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  NEXTCLOUD = {
    :php_nextcloud => {
      :framework => "Nextcloud",
      :language  => "PHP",
      :similar   => ["nextcloud", "php-nextcloud", "php_nextcloud", "nextcloud-app"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
