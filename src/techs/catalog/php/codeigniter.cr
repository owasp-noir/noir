# NoirTechs catalog entry: php_codeigniter.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  CODEIGNITER = {
    :php_codeigniter => {
      :framework => "CodeIgniter",
      :language  => "PHP",
      :similar   => ["codeigniter", "codeigniter4", "php-codeigniter", "php_codeigniter"],
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
