require "../../../spec_helper"
require "../../../../src/detector/detectors/fsharp/*"

describe "Detect F# Giraffe" do
  options = create_test_options
  instance = Detector::Fsharp::Giraffe.new options

  it "paket_dependencies" do
    instance.detect("paket.dependencies", "source https://api.nuget.org/v3/index.json\n\nnuget Giraffe").should be_true
  end

  it "fsproj_with_giraffe" do
    content = "<Project Sdk=\"Microsoft.NET.Sdk.Web\"><ItemGroup><PackageReference Include=\"Giraffe\" Version=\"6.0.0\" /></ItemGroup></Project>"
    instance.detect("App.fsproj", content).should be_true
  end

  it "open_giraffe" do
    content = <<-FSHARP
      open Giraffe

      let webApp = route "/" >=> text "ok"
      FSHARP
    instance.detect("Program.fs", content).should be_true
  end

  it "handler_combinator_usage" do
    content = "let app: HttpHandler = choose [ route \"/x\" >=> text \"\" ]"
    instance.detect("Program.fs", content).should be_true
  end

  it "non_giraffe_fsharp" do
    instance.detect("Program.fs", "let main () = printfn \"hi\"").should be_false
  end

  it "non_fsharp_extension" do
    instance.detect("Program.cs", "open Giraffe").should be_false
  end
end
