# NoirTechs catalog entry: cpp_oatpp.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Cpp
  OATPP = {
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
  }
end
