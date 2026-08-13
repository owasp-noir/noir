# NoirTechs catalog entry: php_slim.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  SLIM = {
    :php_slim => {
      :framework => "Slim",
      :language  => "PHP",
      :similar   => ["slim", "slimframework", "slim-framework", "php-slim", "php_slim", "slim/slim"],
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
