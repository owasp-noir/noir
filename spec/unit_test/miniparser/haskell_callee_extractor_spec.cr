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
end
