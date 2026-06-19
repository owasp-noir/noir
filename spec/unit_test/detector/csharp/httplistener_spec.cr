require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# System.Net.HttpListener" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::CSharp::HttpListener.new options

  it "detects bare HttpListener server setup" do
    instance.detect("Program.cs", <<-CS).should be_true
      using System.Net;

      var listener = new HttpListener();
      listener.Prefixes.Add("http://localhost:8080/");
      listener.Start();
      var context = await listener.GetContextAsync();
      CS
  end

  it "detects fully qualified HttpListener construction" do
    instance.detect("Program.cs", <<-CS).should be_true
      var listener = new System.Net.HttpListener();
      listener.Prefixes.Add("http://localhost:8080/");
      CS
  end

  it "ignores handler-only references without server setup" do
    instance.detect("Handler.cs", "void Handle(HttpListenerContext context) { }").should be_false
  end

  it "ignores unrelated HttpListener type names" do
    instance.detect("Errors.cs", "catch (HttpListenerException ex) { Console.WriteLine(ex); }").should be_false
  end

  it "ignores non-C# files" do
    instance.detect("notes.txt", "var listener = new HttpListener(); listener.Prefixes.Add(\"http://localhost:8080/\");").should be_false
  end
end
