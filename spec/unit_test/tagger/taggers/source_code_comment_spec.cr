require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/source_code_comment.cr"
require "yaml"

FIXTURE_PATH = File.join(__DIR__, "fixtures", "sample_python_app.py")

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "SourceCodeCommentTagger" do
  describe "initialization" do
    it "creates tagger with correct name" do
      tagger = SourceCodeCommentTagger.new(default_tagger_options)
      tagger.name.should eq("source_code_comment")
    end
  end

  describe "perform" do
    it "tags deprecated endpoint from source code comment" do
      tagger = SourceCodeCommentTagger.new(default_tagger_options)

      # Line 8 is the @app.route decorator, line 7 has @deprecated comment
      details = Details.new(PathInfo.new(FIXTURE_PATH, 8))
      endpoint = Endpoint.new("/api/v1/old_endpoint", "GET", [] of Param, details)

      tagger.perform([endpoint])

      tag_names = endpoint.tags.map(&.name)
      tag_names.should contain("deprecated")
    end

    it "tags admin endpoint from source code annotation" do
      tagger = SourceCodeCommentTagger.new(default_tagger_options)

      # Line 14 is the @app.route decorator, line 13 has @admin comment
      details = Details.new(PathInfo.new(FIXTURE_PATH, 14))
      endpoint = Endpoint.new("/admin/users", "GET", [] of Param, details)

      tagger.perform([endpoint])

      tag_names = endpoint.tags.map(&.name)
      tag_names.should contain("admin")
    end

    it "tags internal endpoint" do
      tagger = SourceCodeCommentTagger.new(default_tagger_options)

      # Line 21 is the @app.route decorator, line 20 has @internal comment
      details = Details.new(PathInfo.new(FIXTURE_PATH, 21))
      endpoint = Endpoint.new("/internal/health", "GET", [] of Param, details)

      tagger.perform([endpoint])

      tag_names = endpoint.tags.map(&.name)
      tag_names.should contain("internal")
    end

    it "tags authentication required endpoint" do
      tagger = SourceCodeCommentTagger.new(default_tagger_options)

      # Line 28 is the @app.route decorator, line 27 has @login_required comment
      details = Details.new(PathInfo.new(FIXTURE_PATH, 28))
      endpoint = Endpoint.new("/api/profile", "GET", [] of Param, details)

      tagger.perform([endpoint])

      tag_names = endpoint.tags.map(&.name)
      tag_names.should contain("authentication")
    end

    it "tags rate limited endpoint" do
      tagger = SourceCodeCommentTagger.new(default_tagger_options)

      # Line 34 is the @app.route decorator, line 33 has @rate_limit comment
      details = Details.new(PathInfo.new(FIXTURE_PATH, 34))
      endpoint = Endpoint.new("/api/search", "GET", [] of Param, details)

      tagger.perform([endpoint])

      tag_names = endpoint.tags.map(&.name)
      tag_names.should contain("rate-limited")
    end

    it "tags cached endpoint" do
      tagger = SourceCodeCommentTagger.new(default_tagger_options)

      # Line 40 is the @app.route decorator, line 39 has @Cacheable comment
      details = Details.new(PathInfo.new(FIXTURE_PATH, 40))
      endpoint = Endpoint.new("/api/products", "GET", [] of Param, details)

      tagger.perform([endpoint])

      tag_names = endpoint.tags.map(&.name)
      tag_names.should contain("cached")
    end

    it "tags endpoint with security TODO/FIXME" do
      tagger = SourceCodeCommentTagger.new(default_tagger_options)

      # Line 45 is the @app.route decorator, line 44 has TODO: fix security
      details = Details.new(PathInfo.new(FIXTURE_PATH, 45))
      endpoint = Endpoint.new("/api/vulnerable", "POST", [] of Param, details)

      tagger.perform([endpoint])

      tag_names = endpoint.tags.map(&.name)
      tag_names.should contain("todo-security")
    end

    it "does not tag endpoint without special annotations" do
      tagger = SourceCodeCommentTagger.new(default_tagger_options)

      # Line 92 is the @app.route decorator for public_endpoint with no special annotations nearby
      details = Details.new(PathInfo.new(FIXTURE_PATH, 92))
      endpoint = Endpoint.new("/api/public", "GET", [] of Param, details)

      tagger.perform([endpoint])

      # Should have no tags from source code comments
      tag_names = endpoint.tags.map(&.name)
      tag_names.should_not contain("deprecated")
      tag_names.should_not contain("admin")
      tag_names.should_not contain("internal")
      tag_names.should_not contain("authentication")
      tag_names.should_not contain("rate-limited")
      tag_names.should_not contain("cached")
      tag_names.should_not contain("todo-security")
    end

    it "handles endpoint without code_paths gracefully" do
      tagger = SourceCodeCommentTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/no-source", "GET")

      # Should not raise error, just skip
      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "handles non-existent file path gracefully" do
      tagger = SourceCodeCommentTagger.new(default_tagger_options)

      details = Details.new(PathInfo.new("/non/existent/file.py", 1))
      endpoint = Endpoint.new("/api/missing", "GET", [] of Param, details)

      # Should not raise error, just skip
      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "handles multiple endpoints" do
      tagger = SourceCodeCommentTagger.new(default_tagger_options)

      details1 = Details.new(PathInfo.new(FIXTURE_PATH, 8))
      endpoint1 = Endpoint.new("/api/v1/old_endpoint", "GET", [] of Param, details1)

      details2 = Details.new(PathInfo.new(FIXTURE_PATH, 92))
      endpoint2 = Endpoint.new("/api/public", "GET", [] of Param, details2)

      tagger.perform([endpoint1, endpoint2])

      endpoint1.tags.map(&.name).should contain("deprecated")
      endpoint2.tags.size.should eq(0)
    end
  end
end
