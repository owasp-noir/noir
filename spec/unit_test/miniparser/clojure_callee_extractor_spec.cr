require "../../spec_helper"
require "../../../src/miniparsers/clojure_callee_extractor"

describe Noir::ClojureCalleeExtractor do
  it "extracts nested Clojure calls from handler bodies" do
    body = <<-CLJ
      (let [user (user.service/find-user id)]
        (audit.log/write! "show" user)
        (response/ok (present-user user)))
      CLJ

    callees = Noir::ClojureCalleeExtractor.callees_for_body(body, "core.clj", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"user.service/find-user", 10},
      {"audit.log/write!", 11},
      {"response/ok", 12},
      {"present-user", 12},
    ])
  end

  it "skips comments, strings, quoted forms, and common special forms" do
    body = <<-CLJ
      ; (ignored/comment)
      "(ignored/string)"
      '(ignored/quoted)
      (quote (ignored/again))
      #_(ignored/discarded)
      (safe.service/run!)
      CLJ

    callees = Noir::ClojureCalleeExtractor.callees_for_body(body, "core.clj", 20)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"safe.service/run!", 25},
    ])
  end

  it "keeps namespaced callees that share reserved base names" do
    body = <<-CLJ
      (let [items (db/filter params)]
        (my-service/map items)
        (clojure.core/map identity items))
      CLJ

    callees = Noir::ClojureCalleeExtractor.callees_for_body(body, "core.clj", 30)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"db/filter", 30},
      {"my-service/map", 31},
    ])
  end
end
