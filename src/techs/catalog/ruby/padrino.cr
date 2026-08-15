# NoirTechs catalog entry: ruby_padrino.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Ruby
  PADRINO = {
    :ruby_padrino => {
      # Padrino apps carry Sinatra's own route-registration DSL (every
      # `Padrino::Application` is a `Sinatra::Base` subclass), so the
      # Sinatra detector/analyzer legitimately fire on every Padrino
      # project too — same shape as Lumen/Laravel and Drupal/Symfony.
      # When Padrino is the actual framework, the Sinatra report is
      # redundant noise: `Analyzer::Ruby::Padrino` already re-implements
      # Sinatra's plain `get "/path" do` route matching (so nothing is
      # lost by dropping the Sinatra analyzer) and additionally resolves
      # Padrino's `controllers :name do get :index, map: "..." do end end`
      # named-route DSL and `config/apps.rb` mount-prefix propagation,
      # which the Sinatra analyzer cannot represent at all.
      :supersedes => ["ruby_sinatra"],
      :framework  => "Padrino",
      :language   => "Ruby",
      :similar    => ["padrino", "ruby-padrino", "ruby_padrino", "padrino-core", "padrino-framework"],
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
        :static_path => true,
        :websocket   => false,
      },
      :context => {:callee => true, :guards => true},
    },
  }
end
