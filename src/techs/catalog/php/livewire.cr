# NoirTechs catalog entry: php_livewire.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Php
  LIVEWIRE = {
    :php_livewire => {
      :framework => "Livewire",
      :language  => "PHP",
      :similar   => ["livewire", "php-livewire", "php_livewire", "livewire/livewire", "livewire/volt"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
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
