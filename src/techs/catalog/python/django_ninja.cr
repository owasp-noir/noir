# NoirTechs catalog entry: python_django_ninja.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  DJANGO_NINJA = {
    :python_django_ninja => {
      :framework => "Django Ninja",
      :language  => "Python",
      :similar   => ["django-ninja", "django_ninja", "python-django-ninja", "python_django_ninja", "ninja"],
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
