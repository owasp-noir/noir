require "../../../spec_helper"
require "../../../../src/detector/detectors/haskell/*"

describe "Detect Haskell Scotty" do
  options = create_test_options
  instance = Detector::Haskell::Scotty.new options

  it "package_yaml/dependency" do
    instance.detect("package.yaml", "dependencies:\n  - scotty\n  - warp").should be_true
  end

  it "cabal/dependency" do
    instance.detect("sample.cabal", "build-depends: base, scotty, warp").should be_true
  end

  it "haskell/import_scotty" do
    instance.detect("src/Main.hs", "import Web.Scotty\nmain = pure ()").should be_true
  end

  it "haskell/scotty_call" do
    instance.detect("src/Main.hs", "main = scotty 3000 $ do { get \"/\" $ text \"hi\" }").should be_true
  end

  it "haskell/unrelated" do
    instance.detect("src/Main.hs", "main = putStrLn \"hello\"").should be_false
  end
end
