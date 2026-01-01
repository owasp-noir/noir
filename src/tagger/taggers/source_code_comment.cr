require "../../models/tagger"
require "../../models/endpoint"

class SourceCodeCommentTagger < Tagger
  # Tag definition struct for type safety
  private struct TagDefinition
    getter patterns : Array(Regex)
    getter description : String

    def initialize(@patterns, @description)
    end
  end

  # Common patterns for source code comments and annotations that indicate endpoint classification
  TAG_DEFINITIONS = {
    "deprecated" => TagDefinition.new(
      [
        /@deprecated/i,
        /\bDEPRECATED\b/,
        /\[Obsolete\]/i,
        /\#\s*deprecated/i,
      ],
      "Endpoint is marked as deprecated in source code."
    ),
    "admin" => TagDefinition.new(
      [
        /@admin/i,
        /\badmin[_\-]?only\b/i,
        /\brequires?[_\-]?admin\b/i,
        /\[Authorize\s*\(\s*Roles\s*=\s*["']Admin["']\s*\)\]/i,
        /@RequiresRole\s*\(\s*["']admin["']\s*\)/i,
        /@PreAuthorize.*hasRole.*ADMIN/i,
      ],
      "Endpoint requires admin privileges based on source code annotations."
    ),
    "internal" => TagDefinition.new(
      [
        /@internal/i,
        /\bINTERNAL[_\-]?ONLY\b/i,
        /\bprivate[_\-]?api\b/i,
        /\binternal[_\-]?use\b/i,
      ],
      "Endpoint is marked for internal use only."
    ),
    "authentication" => TagDefinition.new(
      [
        /\[Authorize\]/i,
        /@login[_\-]?required/i,
        /@requires?[_\-]?auth/i,
        /@authenticated/i,
        /\bauth[_\-]?required\b/i,
        /@PreAuthorize/i,
        /@Secured/i,
      ],
      "Endpoint requires authentication based on source code annotations."
    ),
    "rate-limited" => TagDefinition.new(
      [
        /@rate[_\-]?limit/i,
        /@throttle/i,
        /\bthrottle[_\-]?limit/i,
        /\bRateLimit\b/i,
      ],
      "Endpoint has rate limiting applied."
    ),
    "cached" => TagDefinition.new(
      [
        /@cache/i,
        /\[ResponseCache\]/i,
        /\[OutputCache\]/i,
        /@Cacheable/i,
      ],
      "Endpoint response is cached."
    ),
    "todo-security" => TagDefinition.new(
      [
        /TODO.*security/i,
        /FIXME.*security/i,
        /HACK.*auth/i,
        /TODO.*auth/i,
        /FIXME.*auth/i,
        /TODO.*permission/i,
        /FIXME.*permission/i,
      ],
      "Endpoint has security-related TODO/FIXME comments that may indicate incomplete security implementation."
    ),
  }

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "source_code_comment"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      # Skip endpoints without code paths
      next if endpoint.details.code_paths.empty?

      TAG_DEFINITIONS.each do |tag_name, definition|
        # Check if any pattern matches in the source code context
        definition.patterns.each do |pattern|
          if source_contains_pattern?(endpoint, pattern)
            tag = Tag.new(tag_name, definition.description, "SourceCodeComment")
            endpoint.add_tag(tag)
            break # Only add each tag once per endpoint
          end
        end
      end
    end
  end
end
