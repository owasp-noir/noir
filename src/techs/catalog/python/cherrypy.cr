# NoirTechs catalog entry: python_cherrypy.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  CHERRYPY = {
    :python_cherrypy => {
      :framework => "CherryPy",
      :language  => "Python",
      :similar   => ["cherrypy", "cherry-py", "python-cherrypy", "python_cherrypy"],
      :supported => {
        :endpoint => true,
        # CherryPy's default dispatcher is object-traversal, not explicit
        # route registration, so the HTTP method for a plain `@expose`d
        # method is inferred (GET, matching every other analyzer's
        # no-explicit-method convention) rather than declared in source.
        # `MethodDispatcher`-style classes (uppercase GET/POST/PUT/DELETE
        # methods) give a real, explicit method signal.
        :method => true,
        :params => {
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
