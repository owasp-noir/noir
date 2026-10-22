# NoirTechs catalog entry: cpp_crow.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Cpp
  CROW = {
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
