# NoirTechs catalog entry: php_thinkphp.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  THINKPHP = {
    :php_thinkphp => {
      :framework => "ThinkPHP",
      :language  => "PHP",
      :similar   => ["thinkphp", "php-thinkphp", "php_thinkphp"],
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
