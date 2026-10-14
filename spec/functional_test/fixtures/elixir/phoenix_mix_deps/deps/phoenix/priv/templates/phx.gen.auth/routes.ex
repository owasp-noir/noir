
  ## Authentication routes

  scope <%= router_scope %> do
    pipe_through [:browser, :redirect_if_<%= schema.singular %>_is_authenticated]

    get "/<%= schema.plural %>/register", <%= inspect schema.alias %>RegistrationController, :new
    post "/<%= schema.plural %>/register", <%= inspect schema.alias %>RegistrationController, :create
    get "/<%= schema.plural %>/log_in", <%= inspect schema.alias %>SessionController, :new
    post "/<%= schema.plural %>/log_in", <%= inspect schema.alias %>SessionController, :create
  end
