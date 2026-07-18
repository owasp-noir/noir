require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Payload CMS" do
  options = create_test_options
  instance = Detector::Specification::PayloadCms.new options

  collection = <<-TS
    import type { CollectionConfig } from 'payload'

    export const Posts: CollectionConfig = {
      slug: 'posts',
      fields: [
        { name: 'title', type: 'text' },
      ],
    }
    TS

  it "detects a collection config" do
    instance.detect("src/collections/Posts.ts", collection).should be_true
  end

  it "detects the satisfies form" do
    content = <<-TS
      import type { CollectionConfig } from 'payload'

      export const Posts = {
        slug: 'posts',
        fields: [{ name: 'title', type: 'text' }],
      } satisfies CollectionConfig
      TS

    instance.detect("src/collections/Posts.ts", content).should be_true
  end

  it "detects the Payload v2 payload/types import" do
    content = <<-TS
      import { CollectionConfig } from 'payload/types'

      const Posts: CollectionConfig = {
        slug: 'posts',
        fields: [{ name: 'title', type: 'text' }],
      }

      export default Posts
      TS

    instance.detect("collections/Posts.ts", content).should be_true
  end

  it "detects a global config" do
    content = <<-TS
      import type { GlobalConfig } from 'payload'

      export const Settings: GlobalConfig = {
        slug: 'settings',
        fields: [{ name: 'siteName', type: 'text' }],
      }
      TS

    instance.detect("src/globals/Settings.ts", content).should be_true
  end

  it "detects payload.config.ts through buildConfig" do
    content = <<-TS
      import { buildConfig } from 'payload'

      export default buildConfig({
        collections: [],
      })
      TS

    instance.detect("src/payload.config.ts", content).should be_true
  end

  # slug: and fields: are extremely common. Astro content collections,
  # Sanity schemas and Keystone lists all use them; the Payload type name
  # is the discriminator.
  it "ignores a slug/fields object with no Payload type" do
    content = <<-TS
      import { defineCollection, z } from 'astro:content'

      export const blog = defineCollection({
        slug: 'blog',
        fields: [{ name: 'title', type: 'text' }],
      })
      TS

    instance.detect("src/content/config.ts", content).should be_false
  end

  it "ignores a Payload runtime import that declares no config" do
    content = <<-TS
      import { getPayload } from 'payload'

      export async function load() {
        const payload = await getPayload({ config })
        return payload.find({ collection: 'posts' })
      }
      TS

    instance.detect("src/routes/page.ts", content).should be_false
  end

  it "ignores a type-only file that declares no config object" do
    content = <<-TS
      import type { CollectionConfig } from 'payload'

      export type WithTimestamps<T extends CollectionConfig> = T & { timestamps: true }
      TS

    instance.detect("src/types.ts", content).should be_false
  end

  it "ignores declaration and test files" do
    instance.detect("src/collections/Posts.d.ts", collection).should be_false
    instance.detect("src/collections/Posts.test.ts", collection).should be_false
    instance.detect("src/collections/Posts.spec.ts", collection).should be_false
  end

  it "ignores non-JS/TS extensions" do
    instance.detect("collections.json", collection).should be_false
    instance.detect("collections.yaml", collection).should be_false
  end

  it "registers collections, globals and configs under separate keys" do
    locator = CodeLocator.instance
    locator.clear "payload-collection"
    locator.clear "payload-global"
    locator.clear "payload-config"

    instance.detect("src/collections/Posts.ts", collection)
    instance.detect("src/payload.config.ts", "import { buildConfig } from 'payload'\nexport default buildConfig({})")

    locator.all("payload-collection").should eq(["src/collections/Posts.ts"])
    locator.all("payload-config").should eq(["src/payload.config.ts"])
    locator.all("payload-global").should eq([] of String)
  end
end
