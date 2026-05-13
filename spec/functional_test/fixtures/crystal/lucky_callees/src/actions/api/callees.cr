class Api::Callees < Lucky::Action
  get "/lucky/home" do
    data = HomeService.build
    json({home: data})
  end

  post "/lucky/users" do
    payload = params.from_json["user"]
    SaveUser.run(payload) do |_operation, user|
      AuditTrail.record(user)
      json({id: UserPresenter.id(user)})
    end
  end

  put "/lucky/users/:id" do
    id = params.get(:id)
    UserUpdater.call(id)
    json({ok: true})
  end

  delete "/lucky/users/:id" do
    UserDestroyer.call(params.get(:id))
    head 204
  end

  patch "/lucky/users/:id" do
    UserPatch.apply(params.from_query["mode"])
    json({ok: true})
  end

  trace "/lucky/trace" do
    TraceReporter.capture(request.headers["X-Trace"])
    plain_text "ok"
  end
end
