require "../../../spec_helper"
require "../../../../src/detector/detectors/haskell/*"

describe "Detect Haskell Servant" do
  options = create_test_options
  instance = Detector::Haskell::Servant.new options

  it "package_yaml/dependency" do
    instance.detect("package.yaml", "dependencies:\n  - servant\n  - servant-server").should be_true
  end

  it "cabal/dependency" do
    instance.detect("sample.cabal", "build-depends: base, servant, servant-server").should be_true
  end

  it "haskell/import_servant" do
    instance.detect("src/Api.hs", "import Servant\nmain = pure ()").should be_true
  end

  it "haskell/import_servant_qualified" do
    instance.detect("src/Api.hs", "import qualified Servant.API as S\nmain = pure ()").should be_true
  end

  it "haskell/method_combinator" do
    instance.detect("src/Api.hs", "type API = \"users\" :> Get '[JSON] [User]").should be_true
  end

  it "haskell/alternative_combinator" do
    instance.detect("src/Api.hs", "type API = Foo :<|> Bar :> Baz").should be_true
  end

  it "haskell/unrelated" do
    instance.detect("src/Main.hs", "main = putStrLn \"hello\"").should be_false
  end
end
