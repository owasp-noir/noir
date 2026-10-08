# NoirTechs catalog entry: php_api_platform.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  API_PLATFORM = {
    :php_api_platform => {
      :framework => "API Platform",
      :language  => "PHP",
      :similar   => ["api-platform", "api_platform", "php-api-platform", "php_api_platform"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => false,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
