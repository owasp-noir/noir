require "../../../spec_helper"
require "../../../../src/detector/detectors/haskell/*"

describe "Detect Haskell Yesod" do
  options = create_test_options
  instance = Detector::Haskell::Yesod.new options

  it "package_yaml/dependency" do
    instance.detect("package.yaml", "dependencies:\n  - yesod\n  - warp").should be_true
  end

  it "cabal/dependency" do
    instance.detect("sample.cabal", "build-depends: base, yesod-core, yesod").should be_true
  end

  it "haskell/import_yesod" do
    instance.detect("src/Foundation.hs", "import Yesod\nmain = pure ()").should be_true
  end

  it "haskell/parse_routes" do
    instance.detect("src/Foundation.hs", "mkYesodData \"App\" [parseRoutes|/ HomeR GET|]").should be_true
  end

  it "haskell/unrelated" do
    instance.detect("src/Main.hs", "main = putStrLn \"hello\"").should be_false
  end

  it "literate_haskell/applicable" do
    instance.applicable?("src/Foundation.lhs").should be_true
    instance.applicable?("src/Foundation.hs").should be_true
    instance.applicable?("src/Foundation.rs").should be_false
  end

  it "literate_haskell/import_yesod" do
    instance.detect("src/Foundation.lhs", "import Yesod\nmain = pure ()").should be_true
  end
end
