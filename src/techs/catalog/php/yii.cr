# NoirTechs catalog entry: php_yii.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  YII = {
    :php_yii => {
      :framework => "Yii2",
      :language  => "PHP",
      :similar   => ["yii", "yii2", "php-yii", "php_yii", "yiisoft", "yiisoft/yii2"],
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
