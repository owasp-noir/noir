class Home::Index < ApiAction
  include Api::Auth::SkipRequireAuthToken

  # Lucky's `param` macro declares a query parameter at the class level,
  # above the route block.
  param locale : String = "en"

  get "/" do
    json({hello: "Hello World from Home::Index"})
  end
end
