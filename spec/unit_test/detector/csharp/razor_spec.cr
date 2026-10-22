require "../../../spec_helper"
require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# Razor Pages / Blazor" do
  options = create_test_options
  instance = Detector::CSharp::Razor.new options

  it "Razor page without a template" do
    instance.detect("Pages/Index.cshtml", "@page\n@model IndexModel\n").should be_true
  end

  it "Blazor component route" do
    instance.detect("Counter.razor", "@page \"/counter\"\n<h1>Counter</h1>").should be_true
  end

  it "Blazor route attribute" do
    instance.detect("Routed.razor", "@attribute [Route(\"/routed\")]\n").should be_true
  end

  it "escaped CSS @page rule" do
    instance.detect("_Layout.cshtml", "<style>\n@@page { size: A4; }\n</style>").should be_false
  end

  it "view without a directive" do
    instance.detect("Shared/_Layout.cshtml", "<body>@RenderBody()</body>").should be_false
  end
end
