# NoirTechs catalog: dart technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  DART = {
    :dart_cli => {
      :framework => "CLI (args / CommandRunner / dcli)",
      :language  => "Dart",
      :similar   => ["dart-cli", "dart_cli", "args", "dcli", "commandrunner"],
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
    :dart_alfred => {
      :framework => "Alfred",
      :language  => "Dart",
      :similar   => ["alfred", "dart_alfred", "dart-alfred"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
    :dart_angel3 => {
      :framework => "Angel3",
      :language  => "Dart",
      :similar   => ["angel", "angel3", "dart_angel3", "dart-angel3", "angel_framework", "angel3_framework"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
    :dart_get_server => {
      :framework => "GetServer",
      :language  => "Dart",
      :similar   => ["get_server", "getserver", "dart_get_server", "dart-get-server"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
    :dart_frog => {
      :framework => "Dart Frog",
      :language  => "Dart",
      :similar   => ["dart_frog", "dart-frog", "dartfrog", "dart frog"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => true,
      },
      :context => {:callee => true},
    },
    :dart_http => {
      :framework => "dart:io HttpServer",
      :language  => "Dart",
      :similar   => ["dart_http", "dart-http", "dart:io", "dart io", "dart_httpserver", "httpserver"],
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
    },
    :dart_serverpod => {
      :framework => "Serverpod",
      :language  => "Dart",
      :similar   => ["serverpod", "dart_serverpod", "dart-serverpod"],
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
      :context => {:callee => true},
    },
    :dart_shelf => {
      :framework => "Shelf",
      :language  => "Dart",
      :similar   => ["shelf", "dart_shelf", "dart-shelf", "shelf_router", "shelf-router"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
