require "../../spec_helper"
require "../../../src/miniparsers/encore_extractor"

describe Noir::EncoreExtractor do
  it "reads many TS apis of a non-ASCII file in linear time, on the right lines" do
    content = %(import { api } from "encore.dev/api";\nconst title = "한국어";\ninterface Req { id: string; }\n) +
              (0...4000).join { |i| %(export const e#{i} = api({ expose: true, method: "GET", path: "/한/#{i}" }, async (p: Req): Promise<void> => {});\n) }
    apis = [] of Noir::EncoreExtractor::TsApi
    elapsed = Time.measure { apis = Noir::EncoreExtractor.extract_ts(content) }
    apis.size.should eq 4000
    last = apis.last
    {last.name, last.config["path"], last.fields.map(&.name), last.line}.should eq({"e3999", %("/한/3999"), ["id"], 4003})
    elapsed.should be < 2.seconds
  end
end
