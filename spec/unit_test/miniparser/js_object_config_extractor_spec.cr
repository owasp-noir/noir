require "../../spec_helper"
require "../../../src/miniparsers/js_object_config_extractor"

describe Noir::JSObjectConfigExtractor do
  describe ".extract" do
    it "returns nothing for empty source" do
      Noir::JSObjectConfigExtractor.extract("", ["slug"]).should be_empty
    end

    it "returns nothing when no required keys are given" do
      Noir::JSObjectConfigExtractor.extract("export const x = { slug: 'a' }", [] of String).should be_empty
    end

    it "returns nothing when the object is missing a required key" do
      source = "export const Posts = { slug: 'posts' }"
      Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"]).should be_empty
    end

    it "finds an object carrying every required key" do
      source = "export const Posts = { slug: 'posts', fields: [] }"
      configs = Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])
      configs.size.should eq(1)
      configs[0].string("slug").should eq("posts")
    end

    it "reports a 1-based line number for the matched object" do
      source = <<-TS
        // header comment
        export const Posts = {
          slug: 'posts',
          fields: [],
        }
        TS

      Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])[0].line.should eq(2)
    end

    context "declaration shapes" do
      it "reads a TypeScript type-annotated declaration" do
        source = "export const Posts: CollectionConfig = { slug: 'posts', fields: [] }"
        Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])[0]
          .string("slug").should eq("posts")
      end

      it "reads a `satisfies` assertion" do
        source = "export const Posts = { slug: 'posts', fields: [] } satisfies CollectionConfig"
        Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])[0]
          .string("slug").should eq("posts")
      end

      it "reads a generic `satisfies` assertion" do
        source = "export const Posts = { slug: 'posts', fields: [] } satisfies Config<Post>"
        Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])[0]
          .string("slug").should eq("posts")
      end

      it "reads an object nested inside a call argument" do
        source = "export default buildConfig({ collections: [{ slug: 'posts', fields: [] }] })"
        Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])[0]
          .string("slug").should eq("posts")
      end

      it "reads a CommonJS module.exports assignment" do
        source = "module.exports = { slug: 'posts', fields: [] }"
        Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])[0]
          .string("slug").should eq("posts")
      end

      it "reads a let/var declaration" do
        source = "let Posts = { slug: 'posts', fields: [] }; var Pages = { slug: 'pages', fields: [] }"
        Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])
          .map(&.string("slug")).should eq(["posts", "pages"])
      end

      # The type-annotation strip is line-preserving so reported lines
      # still line up with the original source.
      it "keeps line numbers correct after stripping a type annotation" do
        source = <<-TS
          import type { CollectionConfig } from 'payload'

          export const Posts: CollectionConfig = {
            slug: 'posts',
            fields: [],
          }
          TS

        Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])[0].line.should eq(3)
      end
    end

    context "multiple and nested matches" do
      it "finds every sibling object that matches" do
        source = <<-TS
          export const Posts = { slug: 'posts', fields: [] }
          export const Pages = { slug: 'pages', fields: [] }
          TS

        Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])
          .map(&.string("slug")).should eq(["posts", "pages"])
      end

      # A matched object is terminal — descending into it would re-report
      # the same config from an inner object repeating the required keys.
      it "does not re-report a nested object that repeats the required keys" do
        source = <<-TS
          export const Posts = {
            slug: 'posts',
            fields: [],
            admin: { slug: 'inner', fields: [] },
          }
          TS

        configs = Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])
        configs.size.should eq(1)
        configs[0].string("slug").should eq("posts")
      end
    end

    context "value decoding" do
      it "decodes single-quoted, double-quoted and template strings" do
        source = "const c = { a: 'one', b: \"two\", c: `three`, k: 1 }"
        config = Noir::JSObjectConfigExtractor.extract(source, ["a", "b", "c"])[0]
        config.string("a").should eq("one")
        config.string("b").should eq("two")
        config.string("c").should eq("three")
      end

      it "decodes numbers as floats" do
        source = "const c = { method: 'GET', limit: 25 }"
        Noir::JSObjectConfigExtractor.extract(source, ["method", "limit"])[0]["limit"]
          .should eq(25.0)
      end

      it "decodes booleans" do
        source = "const c = { auth: false, enabled: true }"
        config = Noir::JSObjectConfigExtractor.extract(source, ["auth", "enabled"])[0]
        config.bool("auth").should be_false
        config.bool("enabled").should be_true
      end

      it "decodes null and undefined as nil while keeping the key" do
        source = "const c = { auth: null, policy: undefined }"
        config = Noir::JSObjectConfigExtractor.extract(source, ["auth", "policy"])[0]
        config["auth"].should be_nil
        config["policy"].should be_nil
      end

      it "decodes arrays of strings" do
        source = "const c = { routes: ['a', 'b'], name: 'x' }"
        Noir::JSObjectConfigExtractor.extract(source, ["routes", "name"])[0]
          .array("routes").should eq(["a", "b"])
      end

      it "decodes an array of objects" do
        source = <<-TS
          export default {
            routes: [
              { method: 'GET', path: '/things', handler: 'thing.find' },
              { method: 'POST', path: '/things', handler: 'thing.create' },
            ],
          }
          TS

        routes = Noir::JSObjectConfigExtractor.extract(source, ["routes"])[0].array("routes")
        routes.should_not be_nil
        routes.not_nil!.size.should eq(2)

        first = routes.not_nil![0]
        first.should be_a(Hash(String, Noir::JSObjectConfigExtractor::ConfigValue))
        first.as(Hash(String, Noir::JSObjectConfigExtractor::ConfigValue))["path"].should eq("/things")
      end

      it "decodes a nested object value" do
        source = "const c = { name: 'x', config: { auth: false } }"
        nested = Noir::JSObjectConfigExtractor.extract(source, ["name", "config"])[0].hash("config")
        nested.should_not be_nil
        nested.not_nil!["auth"].should be_false
      end

      # Anything not statically resolvable decodes to nil, but the key is
      # still recorded so `has_key?` — and therefore matching — still sees it.
      it "records a key whose value is an arrow function as nil" do
        source = "const c = { slug: 'posts', fields: [], hooks: () => {} }"
        config = Noir::JSObjectConfigExtractor.extract(source, ["slug", "hooks"])[0]
        config["hooks"].should be_nil
        config.string("slug").should eq("posts")
      end

      it "records a key whose value is an identifier as nil but still matches" do
        source = "const c = { slug: 'posts', fields: sharedFields }"
        config = Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])[0]
        config["fields"].should be_nil
      end

      it "decodes a quoted key" do
        source = "const c = { 'slug': 'posts', \"fields\": [] }"
        Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])[0]
          .string("slug").should eq("posts")
      end
    end

    context "ConfigObject accessors" do
      config = Noir::JSObjectConfigExtractor.extract(
        "const c = { s: 'str', b: false, t: true, n: 3, arr: [1], obj: { k: 'v' }, nul: null }",
        ["s", "b", "n"]
      )[0]

      it "returns nil from #string for a non-string value" do
        config.string("n").should be_nil
      end

      it "returns nil from #bool for a non-boolean value" do
        config.bool("s").should be_nil
      end

      it "returns nil from #array for a non-array value" do
        config.array("s").should be_nil
      end

      it "returns nil from #hash for a non-hash value" do
        config.hash("s").should be_nil
      end

      it "returns nil from #[] for a key that is absent" do
        config["missing"].should be_nil
      end

      it "reads an array value" do
        config.array("arr").should eq([1.0])
      end

      it "reads a hash value" do
        config.hash("obj").not_nil!["k"].should eq("v")
      end

      describe "#truthy?" do
        it "is false for an absent key" do
          config.truthy?("missing").should be_false
        end

        it "is false for an explicit false" do
          config.truthy?("b").should be_false
        end

        it "is false for a null value" do
          config.truthy?("nul").should be_false
        end

        it "is true for an explicit true" do
          config.truthy?("t").should be_true
        end

        it "is true for any other present value" do
          config.truthy?("s").should be_true
        end
      end
    end

    context "robustness" do
      it "does not raise on syntactically broken source" do
        Noir::JSObjectConfigExtractor.extract("export const Posts = { slug: 'posts',", ["slug"])
          .should be_a(Array(Noir::JSObjectConfigExtractor::ConfigObject))
      end

      it "does not raise on source with no object literal at all" do
        Noir::JSObjectConfigExtractor.extract("const a = 1; function f() { return a }", ["slug"])
          .should be_empty
      end

      it "stops decoding beyond MAX_VALUE_DEPTH instead of recursing forever" do
        depth = Noir::JSObjectConfigExtractor::MAX_VALUE_DEPTH + 8
        inner = "'leaf'"
        depth.times { inner = "{ n: #{inner} }" }
        source = "const c = { slug: 'posts', fields: #{inner} }"

        configs = Noir::JSObjectConfigExtractor.extract(source, ["slug", "fields"])
        configs.size.should eq(1)
        configs[0].string("slug").should eq("posts")
      end
    end
  end
end
