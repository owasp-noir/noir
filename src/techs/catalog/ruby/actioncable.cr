# NoirTechs catalog entry: ruby_actioncable.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Ruby
  ACTIONCABLE = {
    :ruby_actioncable => {
      :framework => "Action Cable",
      :language  => "Ruby",
      :similar   => ["actioncable", "action-cable", "action_cable", "rails-actioncable", "ruby-actioncable", "ruby_actioncable"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => true,
      },
    },
  }
end
