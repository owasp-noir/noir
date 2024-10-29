class Home::Index < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/" do
    json({hello: "Hello World from Home::Index"})
  end
end
