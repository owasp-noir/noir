require "../../spec_helper"
require "../../../src/miniparsers/swift_callee_extractor"

describe Noir::SwiftCalleeExtractor do
  it "extracts receiver and bare calls from Swift handler bodies" do
    body = <<-SWIFT
      let payload = try req.content.decode(CreateUser.self)
      let user = try UserService.build(payload)
      AuditLog.write("create")
      return user.save(on: req.db).map { saved in
          ResponseBuilder.created(saved)
      }
      SWIFT

    callees = Noir::SwiftCalleeExtractor.callees_for_body(body, "routes.swift", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"req.content.decode", 10},
      {"UserService.build", 11},
      {"AuditLog.write", 12},
      {"user.save", 13},
      {"ResponseBuilder.created", 14},
    ])
  end

  it "skips comments, strings, and Swift control-flow noise" do
    body = <<-SWIFT
      // DangerousService.run()
      let message = "AuditLog.write()"
      /*
       HiddenService.call()
       */
      if shouldAudit {
          SafeService.run()
      }
      switch url.host {
      case "post":
          PostService.run()
      default:
          break
      }
      SWIFT

    callees = Noir::SwiftCalleeExtractor.callees_for_body(body, "routes.swift", 20)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"SafeService.run", 26},
      {"PostService.run", 30},
    ])
  end

  it "tracks nested comments, multiline strings, and trailing closure calls" do
    body = <<-SWIFT
      /*
       OuterService.call()
       /*
        InnerService.call()
        */
       StillHidden.call()
       */
      let template = """
        HiddenService.call()
      """
      dispatch {
        Worker.run()
      }
      SWIFT

    callees = Noir::SwiftCalleeExtractor.callees_for_body(body, "routes.swift", 30)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"dispatch", 40},
      {"Worker.run", 41},
    ])
  end

  describe ".strip_non_code_with_state" do
    strip = ->(line : String, keep : Bool) { Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, 0, false, keep)[0] }

    it "ends a literal after interpolation holding quotes and braces" do
      line = %q(let s = "v: \(req.query["q"] ?? "{")"; f({ x }))
      stripped = strip.call(line, false)
      stripped.size.should eq(line.size)
      stripped.count('{').should eq(1)
      stripped.should end_with("; f({ x })")
      strip.call(line, true).should eq(line)
    end

    it "ends a raw string only at its own hash delimiter" do
      line = %q(let s = #"He said "{" ok"#; g { y }; let t = ##"a"#b"##)
      stripped = strip.call(line, false)
      stripped.count('{').should eq(1)
      stripped.should contain("g { y }")
      stripped.should_not contain("ok")
      stripped.should_not contain("b")
    end

    it "keeps # runs that are not raw strings and stays linear on hostile input" do
      strip.call("#if DEBUG", false).should eq("#if DEBUG")
      hostile = "\"" + "\\(\"" * 20_000
      Time.measure { strip.call(hostile, false) }.should be < 1.second
      Time.measure { strip.call("#" * 100_000, false) }.should be < 1.second
    end
  end
end
