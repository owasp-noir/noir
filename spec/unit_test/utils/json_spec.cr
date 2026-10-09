require "../../../src/utils/*"

describe "json" do
  it "true" do
    json_any?("{\"a\": 1}").should_not be_nil
  end

  it "false" do
    json_any?("{\"a\": 1").should be_nil
  end

  describe "parse_json_lenient" do
    it "reads numbers beyond Int64/Float64 as their raw text" do
      doc = parse_json_lenient(%({"max": 18446744073709551615, "tiny": 1e-400, "list": [-1e400, 7], "s": "1e400"}))
      doc["max"].as_s.should eq("18446744073709551615")
      doc["tiny"].as_s.should eq("1e-400")
      doc["list"][0].as_s.should eq("-1e400")
      doc["list"][1].as_i.should eq(7)
      doc["s"].as_s.should eq("1e400")
      json_any?(%([99999999999999999999])).should_not be_nil
    end

    it "leaves digits inside strings alone" do
      doc = parse_json_lenient(%({"k \\" 99999999999999999999": 99999999999999999999}))
      doc.as_h.keys.should eq([%(k " 99999999999999999999)])
    end

    it "still rejects malformed JSON" do
      expect_raises(JSON::ParseException) { parse_json_lenient(%([99999999999999999999, -])) }
      expect_raises(JSON::ParseException) { parse_json_lenient(%({"a": 1)) }
    end
  end
end
