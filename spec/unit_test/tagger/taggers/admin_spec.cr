require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/admin.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "AdminTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = AdminTagger.new(default_tagger_options)
      tagger.name.should eq("admin")
    end
  end

  describe "perform" do
    it "tags an endpoint under an /admin path" do
      tagger = AdminTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/admin/users", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("admin")
    end

    it "tags a wp-admin path via the admin token" do
      tagger = AdminTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/wp-admin/options.php", "POST")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("admin")
    end

    it "tags an endpoint with a privilege-mutation parameter" do
      tagger = AdminTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/users/42", "PATCH", [
        Param.new("is_admin", "true", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("admin")
    end

    it "tags a camelCase privilege-mutation parameter" do
      tagger = AdminTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/users/42", "PATCH", [
        Param.new("isSuperuser", "true", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("admin")
    end

    it "tags a superadmin path segment" do
      tagger = AdminTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/superadmin/settings", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("admin")
    end

    it "tags a weak privilege parameter only on a state-changing method" do
      tagger = AdminTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/session", "POST", [
        Param.new("run_as", "root", "json"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("admin")
    end

    it "does not tag a weak privilege parameter used as a read-only filter" do
      tagger = AdminTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/roles", "GET", [
        Param.new("privilege", "read", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag a benign path that merely contains the substring" do
      tagger = AdminTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/badminton/courts", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag a regular endpoint" do
      tagger = AdminTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/products", "GET", [
        Param.new("page", "1", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end
  end
end
