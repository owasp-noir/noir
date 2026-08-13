# NoirTechs catalog entry: ruby_rails.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Ruby
  RAILS = {
    :ruby_rails => {
      :framework => "Rails",
      :language  => "Ruby",
      :similar   => ["rails", "ruby-rails", "ruby_rails"],
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
