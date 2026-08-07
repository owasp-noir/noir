# NoirTechs catalog: cpp technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  CPP = {
    :cpp_cli => {
      :framework => "CLI (CLI11 / getopt / cxxopts / boost.program_options / gflags / Abseil Flags / argparse)",
      :language  => "C++",
      :similar   => ["cpp-cli", "cpp_cli", "cli11", "getopt", "cxxopts", "program_options", "gflags", "abseil", "absl-flags", "argparse"],
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
    :cpp_drogon => {
      :framework => "Drogon",
      :language  => "C++",
      :similar   => ["drogon", "cpp-drogon", "cpp_drogon", "c++-drogon", "c++_drogon"],
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
      :context => {:callee => true},
    },
    :cpp_httplib => {
      :framework => "cpp-httplib",
      :language  => "C++",
      :similar   => ["httplib", "cpp-httplib", "cpp_httplib", "c++-httplib", "c++_httplib", "yhirose-httplib"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
    :cpp_oatpp => {
      :framework => "oat++",
      :language  => "C++",
      :similar   => ["oatpp", "oat++", "cpp-oatpp", "cpp_oatpp", "c++-oatpp", "c++_oatpp"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
    :cpp_crow => {
      :framework => "Crow",
      :language  => "C++",
      :similar   => ["crow", "crowcpp", "crow-cpp", "cpp-crow", "cpp_crow", "c++-crow", "c++_crow"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => true,
      },
      :context => {:callee => true},
    },
  }
end
