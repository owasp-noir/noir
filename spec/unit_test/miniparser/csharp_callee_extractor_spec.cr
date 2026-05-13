require "../../spec_helper"
require "../../../src/miniparsers/csharp_callee_extractor"

describe Noir::CSharpCalleeExtractor do
  it "extracts method calls from C# handler blocks with line numbers" do
    body = <<-CS
      public IActionResult Show(int id)
      {
        var order = orderService.Load(id);
        AuditLog.Write("show");
        return Ok(SerializeOrder(order));
      }
      CS

    callees = Noir::CSharpCalleeExtractor.callees_for_block(body, "OrdersController.cs", 10, skip_first_line: true)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"orderService.Load", 12},
      {"AuditLog.Write", 13},
      {"Ok", 14},
      {"SerializeOrder", 14},
    ])
  end

  it "skips route builder wrappers and comments in minimal API blocks" do
    body = <<-CS
      routeBuilder.MapPost("/orders", async context =>
      {
        // ignoredCall()
        var saved = await orderService.Save(context);
        await context.Response.WriteAsync(SerializeOrder(saved));
      });
      CS

    callees = Noir::CSharpCalleeExtractor.callees_for_block(body, "OrderEndpoint.cs", 20)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"orderService.Save", 23},
      {"context.Response.WriteAsync", 24},
      {"SerializeOrder", 24},
    ])
  end

  it "skips direct constructor chaining calls while keeping this member calls" do
    body = <<-CS
      public OrdersController() : this()
      {
        this();
        this.orderService.Save();
        base();
        base.Initialize();
      }
      CS

    callees = Noir::CSharpCalleeExtractor.callees_for_block(body, "OrdersController.cs", 30, skip_first_line: true)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"this.orderService.Save", 33},
      {"base.Initialize", 35},
    ])
  end
end
