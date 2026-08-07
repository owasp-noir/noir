# NoirTechs catalog: ruby technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  RUBY = {
    :ruby_cli => {
      :framework => "CLI (OptionParser / Thor / GLI / Slop / TTY::Option / Optimist / Clamp / dry-cli)",
      :language  => "Ruby",
      :similar   => ["ruby-cli", "ruby_cli", "thor", "optparse", "optionparser", "gli", "slop", "tty-option", "optimist", "clamp", "dry-cli"],
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
        :websocket   => false,
      },
    },
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
    :ruby_grape => {
      :framework => "Grape",
      :language  => "Ruby",
      :similar   => ["grape", "ruby-grape", "ruby_grape"],
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
    :ruby_hanami => {
      :framework => "Hanami",
      :language  => "Ruby",
      :similar   => ["hanami", "ruby-hanami", "ruby_hanami"],
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
    :ruby_roda => {
      :framework => "Roda",
      :language  => "Ruby",
      :similar   => ["roda", "ruby-roda", "ruby_roda"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => false,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true, :guards => true},
    },
    :ruby_sinatra => {
      :framework => "Sinatra",
      :language  => "Ruby",
      :similar   => ["sinatra", "ruby-sinatra", "ruby_sinatra"],
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
    :ruby_webrick => {
      :framework => "WEBrick",
      :language  => "Ruby",
      :similar   => ["webrick", "ruby-webrick", "ruby_webrick", "WEBrick::HTTPServer", "mount_proc", "AbstractServlet"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
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
