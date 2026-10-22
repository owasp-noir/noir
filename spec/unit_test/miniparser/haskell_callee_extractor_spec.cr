require "../../spec_helper"
require "../../../src/miniparsers/haskell_callee_extractor"

describe Noir::HaskellCalleeExtractor do
  it "extracts top-level Haskell function bodies" do
    source = <<-HASKELL
      module Handler.Home where

      getHomeR :: Handler Html
      getHomeR = do
        users <- loadUsers
        defaultLayout $ renderUsers users

      helper = do
        pure ()
      HASKELL

    bodies = Noir::HaskellCalleeExtractor.function_bodies(source, "Handler/Home.hs")
    bodies.map { |body| {body[:name], body[:start_line]} }.should eq([
      {"getHomeR", 4},
      {"helper", 8},
    ])
  end

  it "keeps scanning after Servant promoted type lists" do
    source = <<-HASKELL
      type API = "users" :> Get '[JSON] User

      server = handler

      handler = do
        value <- loadValue
        return value
      HASKELL

    bodies = Noir::HaskellCalleeExtractor.function_bodies(source, "Api.hs")
    bodies.map { |body| {body[:name], body[:start_line]} }.should eq([
      {"server", 3},
      {"handler", 5},
    ])
  end

  it "treats a binding with an inline body annotation as a definition" do
    source = <<-HASKELL
      apiInfo :: Info
      apiInfo = buildInfo (Proxy :: Proxy API)

      typed = decode payload :: Maybe Value
      HASKELL

    bodies = Noir::HaskellCalleeExtractor.function_bodies(source, "Api.hs")
    bodies.map { |body| body[:name] }.should eq(["apiInfo", "typed"])

    apiinfo = bodies.find! { |body| body[:name] == "apiInfo" }
    callees = Noir::HaskellCalleeExtractor.callees_for_body(apiinfo[:body], apiinfo[:path], apiinfo[:start_line])
    callees.map { |name, _, _| name }.should contain("buildInfo")
  end

  it "extracts the body past a same-line guard comparison" do
    # The binding `=` follows a `==` guard; splitting on the first `=` would
    # capture `= 0 = handleZero n` instead of the real body.
    source = <<-HASKELL
      classify n | n == 0 = handleZero n
      HASKELL

    bodies = Noir::HaskellCalleeExtractor.function_bodies(source, "X.hs")
    body = bodies.first
    body[:name].should eq("classify")
    callees = Noir::HaskellCalleeExtractor.callees_for_body(body[:body], body[:path], body[:start_line])
    names = callees.map { |name, _, _| name }
    names.should contain("handleZero")
  end

  it "extracts direct calls from Haskell handler bodies" do
    body = <<-HASKELL
      do
        users <- loadUsers
        account <- Account.Service.fetch userId
        defaultLayout $ do
          setTitle "Ignored.call()"
          toWidget [lucius|
            .ignored { color: red; }
          |]
          renderUsers users
        sendResponseStatus status201 account
      HASKELL

    callees = Noir::HaskellCalleeExtractor.callees_for_body(body, "Handler/Home.hs", 20)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"loadUsers", 21},
      {"Account.Service.fetch", 22},
      {"defaultLayout", 23},
      {"setTitle", 24},
      {"toWidget", 25},
      {"renderUsers", 28},
      {"sendResponseStatus", 29},
    ])
  end

  it "skips comments, strings, chars, quasiquotes, and common builtins" do
    body = <<-HASKELL
      do
        -- Ignored.line()
        {- Ignored.block() -}
        _ <- pure "Ignored.string()"
        _ <- pure 'x'
        html <- [whamlet|Ignored.template()|]
        realCall html
      HASKELL

    callees = Noir::HaskellCalleeExtractor.callees_for_body(body, "Handler/Home.hs", 40)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"realCall", 46},
    ])
  end

  it "extracts inline branch calls and skips local type signatures" do
    body = <<-HASKELL
      do
        query :: SqlQuery
        case found of
          Just user -> returnJson user
          Nothing -> notFound
        if ok then redirect HomeR else invalidArgs ["bad"]
      HASKELL

    callees = Noir::HaskellCalleeExtractor.callees_for_body(body, "Handler/Home.hs", 60)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"returnJson", 63},
      {"notFound", 64},
      {"redirect", 65},
      {"invalidArgs", 65},
    ])
  end

  # Regression: a `'` glued to an identifier matched the <= 8 character
  # char-literal heuristic, so `xs' <- go' 1` was masked from the first
  # prime to the second — `go'` disappeared and the leftover `xs` was
  # reported as a phantom callee.
  it "treats a prime as part of the identifier, not the start of a char literal" do
    body = <<-HASKELL
      do
        xs' <- go' 1
        pure xs'
      HASKELL

    callees = Noir::HaskellCalleeExtractor.callees_for_body(body, "Handler/Home.hs", 10)
    names = callees.map { |name, _, _| name }
    names.should contain("go'")
    names.should_not contain("xs")
  end

  it "handles a primed identifier sitting next to a real char literal" do
    body = <<-HASKELL
      do
        xs' <- splitOn' ','
        render' xs'
      HASKELL

    callees = Noir::HaskellCalleeExtractor.callees_for_body(body, "Handler/Home.hs", 20)
    names = callees.map { |name, _, _| name }
    # The primes belong to the identifiers; `','` is preceded by a space, so
    # it is still a genuine char literal and stays masked.
    names.should eq(["splitOn'", "render'"])
  end

  it "keeps the prime on a primed top-level function name" do
    source = <<-HASKELL
      module Handler.Home where

      getHomeR' :: Handler Html
      getHomeR' = do
        pure ()
      HASKELL

    bodies = Noir::HaskellCalleeExtractor.function_bodies(source, "Handler/Home.hs")
    bodies.map { |body| body[:name] }.should eq(["getHomeR'"])
  end
end
