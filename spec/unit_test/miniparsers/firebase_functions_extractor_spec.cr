require "../../spec_helper"
require "../../../src/miniparsers/firebase_functions_extractor"

describe Noir::FirebaseFunctionsExtractor do
  it "reads v1 chains, v2 calls and typed exports" do
    content = <<-JS
      const functions = require("firebase-functions");
      exports.a = functions.region(defineString("R")).https.onRequest(app);
      module.exports.b = functions.https.onCall((data) => data);
      export const c: HttpsFunction = onRequest({ cors: true }, (req, res) => {});
      export const d = onCallGenkit(flow);
      JS
    triggers = Noir::FirebaseFunctionsExtractor.extract(content)
    triggers.map { |t| {t.name, t.kind, t.line} }.should eq [
      {"a", "onRequest", 2}, {"b", "onCall", 3}, {"c", "onRequest", 4}, {"d", "onCallGenkit", 5},
    ]
    triggers[0].args.should eq "app"
  end

  it "skips non-HTTPS triggers, comments and files without firebase-functions" do
    Noir::FirebaseFunctionsExtractor.extract(%(require("firebase-functions");\nexports.x = functions.firestore.document("a").onCreate(h);\n// exports.y = functions.https.onRequest(h);)).should be_empty
    Noir::FirebaseFunctionsExtractor.extract(%(exports.y = https.onRequest(h);)).should be_empty
  end

  it "reads many triggers of a non-ASCII file in linear time, on the right lines" do
    content = %(const functions = require("firebase-functions");\nconst title = "한국어";\n) +
              (0...4000).join { |i| %(exports.f#{i} = functions.https.onRequest((req, res) => res.send("한 #{i}"));\n) }
    triggers = [] of Noir::FirebaseFunctionsExtractor::Trigger
    elapsed = Time.measure { triggers = Noir::FirebaseFunctionsExtractor.extract(content) }
    triggers.size.should eq 4000
    {triggers.last.name, triggers.last.args, triggers.last.line}.should eq({"f3999", %((req, res) => res.send("한 3999")), 4002})
    elapsed.should be < 2.seconds
  end
end
