require "../../spec_helper"
require "../../../src/miniparsers/scala_callee_extractor"

describe Noir::ScalaCalleeExtractor do
  it "extracts receiver and bare calls from Scala handler bodies" do
    body = <<-SCALA
      val user = UserService.find(params("id"))
      AuditLog.write("show", user.id)
      json(serializeUser(user))
      SCALA

    callees = Noir::ScalaCalleeExtractor.callees_for_body(body, "Routes.scala", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"UserService.find", 10},
      {"params", 10},
      {"AuditLog.write", 11},
      {"json", 12},
      {"serializeUser", 12},
    ])
  end

  it "normalizes spaced receiver calls and multiline receiver chains" do
    body = <<-SCALA
      val users = UserService
        .list()
      val profile = ProfileService . load(user.id)
      SCALA

    callees = Noir::ScalaCalleeExtractor.callees_for_body(body, "Routes.scala", 40)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"UserService.list", 41},
      {"ProfileService.load", 42},
    ])
  end

  it "skips comments, strings, multiline strings, and common Scala keywords" do
    body = <<-SCALA
      // IgnoredService.run()
      val literal = "UserService.create()"
      val template = """
        AuditLog.write()
      """
      if (enabled) {
        SafeService.run()
      }
      SCALA

    callees = Noir::ScalaCalleeExtractor.callees_for_body(body, "Routes.scala", 20)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"SafeService.run", 26},
    ])
  end

  it "skips block comments across lines" do
    body = <<-SCALA
      /*
       * DangerousService.run()
       */
      SafeService.run()
      SCALA

    callees = Noir::ScalaCalleeExtractor.callees_for_body(body, "Routes.scala", 30)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"SafeService.run", 33},
    ])
  end
end
