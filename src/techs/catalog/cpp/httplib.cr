# NoirTechs catalog entry: cpp_httplib.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Cpp
  HTTPLIB = {
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
  }
end
