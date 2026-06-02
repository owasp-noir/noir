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

  it "captures var-quoted handler references but still skips plain quotes" do
    body = <<-CLJ
      (wrap #'user-ctl/default)
      (route #'show-handler)
      '(ignored/quoted)
      CLJ

    callees = Noir::ClojureCalleeExtractor.callees_for_body(body, "core.clj", 40)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"wrap", 40},
      {"user-ctl/default", 40},
      {"route", 41},
      {"show-handler", 41},
    ])
  end

  it "skips arithmetic/comparison operators and binding macros" do
    body = <<-CLJ
      (if-let [u (db/find id)]
        (response/ok (/ (+ (:a u) (:b u)) (math/scale 2)))
        (when-some [d (db/default)]
          (response/ok (= d (compute/value d)))))
      CLJ

    callees = Noir::ClojureCalleeExtractor.callees_for_body(body, "core.clj", 1)
    callees.map(&.[0]).should eq([
      "db/find",
      "response/ok",
      "math/scale",
      "db/default",
      "response/ok",
      "compute/value",
    ])
  end

  it "captures syntax-quoted handler symbols and drops collection plumbing" do
    body = <<-CLJ
      (conj common-interceptors `home-page)
      (into [] `app.handlers/show)
      `(ignored template)
      CLJ

    callees = Noir::ClojureCalleeExtractor.callees_for_body(body, "core.clj", 1)
    callees.map(&.[0]).should eq([
      "home-page",
      "app.handlers/show",
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

  it "collects callees from top-level defn bodies" do
    source = <<-CLJ
      (ns demo.core)

      (defn ^:private show-user
        "Loads a user"
        [request]
        (let [user (user.service/find (:id request))]
          (audit/write! "show" user)
          (response/ok (present-user user))))

      (defn ^String ^{:private true} ignored []
        '(quoted/call)
        #_(discarded/call)
        (safe/run!))
      CLJ

    callees = Noir::ClojureCalleeExtractor.function_callees(source, "core.clj")

    callees["show-user"].map { |name, _, line| {name, line} }.should eq([
      {"user.service/find", 6},
      {"audit/write!", 7},
      {"response/ok", 8},
      {"present-user", 8},
    ])
    callees["ignored"].map(&.[0]).should eq(["safe/run!"])
  end
end
