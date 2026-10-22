# NoirTechs catalog entry: php_cakephp.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  CAKEPHP = {
    :php_cakephp => {
      :framework => "CakePHP",
      :language  => "PHP",
      :similar   => ["cakephp", "php-cakephp", "php_cakephp"],
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
        :static_path => true,
        :websocket   => false,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
