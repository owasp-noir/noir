# NoirTechs catalog entry: php_lumen.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  LUMEN = {
    :php_lumen => {
      # Lumen and Laravel share enough surface (Illuminate namespaces, the
      # `routes/` convention) that the Laravel detector also fires on Lumen
      # projects. When Lumen is the actual framework, the Laravel signal is
      # just noise.
      :supersedes => ["php_laravel"],
      :framework  => "Lumen",
      :language   => "PHP",
      :similar    => ["lumen", "php-lumen", "php_lumen", "laravel/lumen", "laravel-lumen", "lumen-framework"],
      :supported  => {
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
      :context => {:callee => true},
    },
  }
end
