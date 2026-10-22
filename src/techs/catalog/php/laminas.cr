# NoirTechs catalog entry: php_laminas.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  LAMINAS = {
    :php_laminas => {
      :framework => "Laminas",
      :language  => "PHP",
      :similar   => ["laminas", "zend", "zend-framework", "zendframework", "php-laminas", "php_laminas", "laminas/laminas-mvc", "mezzio", "mezzio/mezzio"],
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
