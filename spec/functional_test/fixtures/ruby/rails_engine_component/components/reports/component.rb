module Reports
  class Component < ::Rails::Engine
    isolate_namespace Reports
    routes.default_scope = {}
  end
end
