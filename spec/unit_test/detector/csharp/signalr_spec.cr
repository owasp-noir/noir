require "../../../spec_helper"
require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# SignalR" do
  options = create_test_options
  instance = Detector::CSharp::SignalR.new options

  it "detects the SignalR namespace in a hub file" do
    hub = <<-CS
      using Microsoft.AspNetCore.SignalR;

      public class ChatHub : Hub
      {
          public Task Send(string msg) => Clients.All.SendAsync("recv", msg);
      }
      CS
    instance.detect("ChatHub.cs", hub).should be_true
  end

  it "detects a MapHub<T> mount" do
    program = <<-CS
      var app = builder.Build();
      app.MapHub<ChatHub>("/chat");
      app.Run();
      CS
    instance.detect("Program.cs", program).should be_true
  end

  it "ignores a plain C# file with no SignalR markers" do
    instance.detect("Foo.cs", "public class Foo { public int X; }").should be_false
  end

  it "is not applicable to non-.cs files" do
    instance.applicable?("Program.fs").should be_false
  end
end
