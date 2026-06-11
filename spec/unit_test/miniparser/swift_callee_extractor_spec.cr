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
end
