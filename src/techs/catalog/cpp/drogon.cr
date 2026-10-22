# NoirTechs catalog entry: cpp_drogon.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Cpp
  DROGON = {
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
  }
end
